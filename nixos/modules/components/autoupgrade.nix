{ config, pkgs, ... }:

let
  username = "taylor";
  userHome = config.users.users.${username}.home;

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
in
{
  system.autoUpgrade = {
    enable = true;
    dates = "daily";
    persistent = true;
    flake = "${userHome}/.dotfiles/nixos";
    allowReboot = false;
  };

  systemd.services.nixos-upgrade.serviceConfig.ExecStartPre = [ "${preUpgrade}" ];

  nix.gc = {
    automatic = true;
    dates = "daily";
    persistent = true;
    options = "--delete-older-than 7d";
  };
}