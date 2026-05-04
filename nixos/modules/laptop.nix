{ config, pkgs, ... }:

{
  imports = [
    ./components/asus-laptop.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/niri.nix
    ./components/thunar.nix
  ];

  programs = {
    obs-studio.enable = true;
  };

  environment.systemPackages = with pkgs; [
    vscodium
  ];
}