{ config, pkgs, ... }:

let
  username = "taylor";
  userHome = config.users.users.${username}.home;

  preUpgrade = pkgs.writeShellScript "nixos-upgrade-pre" ''
    set -euo pipefail
    ${pkgs.util-linux}/bin/runuser -u ${username} -- ${pkgs.bash}/bin/bash -c '
      set -euo pipefail
      DOTFILES="$HOME/.dotfiles"
      DEST="$DOTFILES/nixos/hosts/$(${pkgs.nettools}/bin/hostname)/hardware-configuration.nix"

      ${pkgs.git}/bin/git -C "$DOTFILES" pull --rebase --autostash
      ${pkgs.coreutils}/bin/cp -f /etc/nixos/hardware-configuration.nix "$DEST"
      ${pkgs.git}/bin/git -C "$DOTFILES" add -f \
        "nixos/hosts/$(${pkgs.nettools}/bin/hostname)/hardware-configuration.nix"
    '
  '';
in
{
  system.autoUpgrade = {
    enable = true;
    dates = "daily";
    persistent = true;
    flake = "${userHome}/.dotfiles/nixos";
    flags = [ "--update-input" "nixpkgs" ];
    allowReboot = false;
  };

  systemd.services.nixos-upgrade.serviceConfig.ExecStartPre = [ "${preUpgrade}" ];

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
}