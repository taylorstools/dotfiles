{ config, ... }:

let
  username = "taylor";
in
{
  # Automatic updates
  system.autoUpgrade = {
    enable = true;
    dates = "daily";
    persistent = true;
    flake = "${config.users.users.${username}.home}/.dotfiles/nixos";
    flags = [
      "--update-input" "nixpkgs"
    ];
    allowReboot = false;
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
}