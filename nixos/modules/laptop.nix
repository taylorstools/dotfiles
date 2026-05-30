{ pkgs, ... }:

{
  imports = [
    ./components/asus-laptop.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/niri.nix
    ./components/thunar.nix
  ];

  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = true;

  programs = {
    obs-studio.enable = true;
  };

  myOptions = {
    dms.source = "git";
    quickshell.source = "git";
  };

  environment.systemPackages = with pkgs; [
    mprime
    obsidian
    vscodium
  ];
}