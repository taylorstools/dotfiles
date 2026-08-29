{ config, pkgs, lib, ... }:

let
  username = config.myOptions.user.name;
  userHome = config.users.users.${username}.home;
  logFile = "${userHome}/upgrade.log";

  statusDir = "/var/lib/nixos-upgrade";
  statusFile = "${statusDir}/last-status";

  preUpgrade = pkgs.writeShellScript "nixos-upgrade-pre" ''
    set -euo pipefail
    ${pkgs.util-linux}/bin/runuser -u ${username} -- ${pkgs.bash}/bin/bash -c '
      set -euo pipefail
      DOTFILES="${userHome}/.dotfiles"
      ETC_NIXOS="/etc/nixos"
      HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
      HOST_DIR="$DOTFILES/nixos/hosts/$HOSTNAME"
      LOCKFILE="$DOTFILES/nixos/flake.lock"

      SYNC_FILES=(
        hardware-configuration.nix
        hostid.nix
        disko.nix
        luks-tpm-autounlock.nix
      )

      if [ ! -d "$HOST_DIR" ]; then
        echo "Host directory $HOST_DIR does not exist" >&2
        exit 1
      fi

      if [ -f "$LOCKFILE" ]; then
        rm -f "$LOCKFILE"
        ${pkgs.git}/bin/git -C "$DOTFILES" rm nixos/flake.lock --ignore-unmatch
      fi

      ${pkgs.git}/bin/git -C "$DOTFILES" pull --rebase --autostash

      for f in "''${SYNC_FILES[@]}"; do
        SRC="$ETC_NIXOS/$f"
        DST="$HOST_DIR/$f"
        [ -f "$SRC" ] || continue
        if [ -f "$DST" ] && ${pkgs.diffutils}/bin/cmp -s "$SRC" "$DST"; then
          continue
        fi
        ${pkgs.coreutils}/bin/cp -f "$SRC" "$DST"
        ${pkgs.git}/bin/git -C "$DOTFILES" add -f \
          "nixos/hosts/$HOSTNAME/$f"
      done

      ${pkgs.nix}/bin/nix flake update --flake "$DOTFILES/nixos"
    '
  '';

  # Runs after every nixos-upgrade run (including ExecStartPre failures) and
  # records systemd's verdict so the next boot can report on it.
  recordStatus = pkgs.writeShellScript "nixos-upgrade-record-status" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/install -d -m 0755 ${statusDir}
    {
      echo "result=''${SERVICE_RESULT:-unknown}"
      echo "exit-status=''${EXIT_STATUS:-}"
      echo "finished=$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
    } > ${statusFile}
  '';

  notifyFailure = pkgs.writeShellApplication {
    name = "upgrade-failure-notify";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.libnotify pkgs.systemd ];
    text = ''
      StatusFile="${statusFile}"
      StampFile="$XDG_RUNTIME_DIR/upgrade-failure-notified"

      # Only nag once per boot, not once per session start.
      if [ -e "$StampFile" ]; then
        echo "Already notified this boot; nothing to do."
        exit 0
      fi

      if [ ! -r "$StatusFile" ]; then
        echo "No upgrade status recorded yet at $StatusFile."
        exit 0
      fi

      Result="$(grep -m1 '^result=' "$StatusFile" | cut -d= -f2- || true)"
      if [ "$Result" = "success" ]; then
        echo "Last automatic upgrade succeeded."
        exit 0
      fi

      echo "Last automatic upgrade result: ''${Result:-unknown}"

      # The session bus exists before the notification daemon claims its name,
      # so wait for an owner rather than firing into the void.
      Waited=0
      until busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
              org.freedesktop.DBus NameHasOwner s org.freedesktop.Notifications \
              2>/dev/null | grep -q true; do
        if [ "$Waited" -ge 60 ]; then
          echo "No notification daemon appeared within ''${Waited}s; giving up." >&2
          exit 0
        fi
        sleep 2
        Waited=$((Waited + 2))
      done

      notify-send \
        --app-name="NixOS Upgrade" \
        --urgency=critical \
        --icon=dialog-error \
        "Last automatic upgrade failed. Review the log." \
        "${logFile}"

      : > "$StampFile"
    '';
  };
in
{
  systemd.services.NetworkManager-wait-online.enable = true;
  systemd.network.wait-online.enable = false;

  system.autoUpgrade = {
    enable = true;
    dates = "daily";
    persistent = true;
    flake = "${userHome}/.dotfiles/nixos";
    allowReboot = false;
  };

  systemd.services.nixos-upgrade.serviceConfig = {
    StandardOutput = "append:${logFile}";
    ExecStartPre = [
      "${pkgs.coreutils}/bin/truncate -s 0 ${logFile}"
      "${pkgs.coreutils}/bin/chown ${username}:users ${logFile}"
      "${preUpgrade}"
    ];
    ExecStopPost = [ "${recordStatus}" ];
  };

  systemd.user.services.upgrade-failure-notify = {
    description = "Notify if the last automatic NixOS upgrade failed";
    after = [ "graphical-session.target" ];
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe notifyFailure;
      TimeoutStartSec = "120s";
    };
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    persistent = true;
    options = "--delete-older-than 7d";
  };
}
