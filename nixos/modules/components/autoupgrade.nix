{ config, pkgs, ... }:

let
  username = "taylor";
  userHome = config.users.users.${username}.home;

  preUpgrade = pkgs.writeShellScript "nixos-upgrade-pre" ''
    set -euo pipefail
    ${pkgs.util-linux}/bin/runuser -u ${username} -- ${pkgs.bash}/bin/bash -c '
      set -euo pipefail
      DOTFILES="${userHome}/.dotfiles"
      HWCONFIG="/etc/nixos/hardware-configuration.nix"
      HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
      DEST="$DOTFILES/nixos/hosts/$HOSTNAME/hardware-configuration.nix"
      LOCKFILE="$DOTFILES/nixos/flake.lock"

      if [ -f "$LOCKFILE" ]; then
        rm -f "$LOCKFILE"
        ${pkgs.git}/bin/git -C "$DOTFILES" rm nixos/flake.lock --ignore-unmatch
      fi

      ${pkgs.git}/bin/git -C "$DOTFILES" pull --rebase --autostash

      if [ ! -f "$HWCONFIG" ]; then
        echo "$HWCONFIG does not exist!" >&2
        exit 1
      fi

      if ! ${pkgs.diffutils}/bin/cmp -s "$HWCONFIG" "$DEST"; then
        ${pkgs.coreutils}/bin/cp -f "$HWCONFIG" "$DEST"
        ${pkgs.git}/bin/git -C "$DOTFILES" add -f \
          "nixos/hosts/$HOSTNAME/hardware-configuration.nix"
      fi

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