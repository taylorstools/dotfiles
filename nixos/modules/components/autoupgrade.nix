{ config, pkgs, ... }:

let
  username = config.myOptions.user.name;
  userHome = config.users.users.${username}.home;
  logFile = "${userHome}/upgrade.log";

  preUpgrade = pkgs.writeShellScript "nixos-upgrade-pre" ''
    set -euo pipefail
    ${pkgs.util-linux}/bin/runuser -u ${username} -- ${pkgs.bash}/bin/bash -c '
      set -euo pipefail
      DOTFILES="${userHome}/.dotfiles"
      ETC_NIXOS="/etc/nixos"
      HOST_DIR="$DOTFILES/nixos/hosts/${config.networking.hostName}"

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
          "nixos/hosts/${config.networking.hostName}/$f"
      done

      ${pkgs.nix}/bin/nix flake update --flake "$DOTFILES/nixos" --commit-lock-file
    '
  '';
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
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    persistent = true;
    options = "--delete-older-than 15d";
  };
}