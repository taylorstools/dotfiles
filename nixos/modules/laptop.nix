{ config, pkgs, ... }:

{
  imports = [
    ./components/dms.nix
    ./components/greetd.nix
    ./components/niri.nix
    ./components/thunar.nix
  ];
  
  services.asusd = {
    enable = true;
    enableUserService = true;
  };

  programs = {
    obs-studio.enable = true;
  };

  environment.systemPackages = with pkgs; [
    vscodium
  ];
}