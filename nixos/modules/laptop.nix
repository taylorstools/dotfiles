{ pkgs, lib, ... }:

{
  imports = [
    ./components/asus-laptop.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/niri.nix
    ./components/power-management.nix
    ./components/remmina.nix
    ./components/thunar.nix
  ];

  programs = {
    obs-studio.enable = true;
    localsend.enable = true;
  };

  myOptions = {
    dms.source = "stable";
    quickshell.source = "stable";
  };

  environment.systemPackages = with pkgs; [
    kdePackages.krdc
    obsidian
    sysboard
    vscodium
    moonlight-qt
  ];
}