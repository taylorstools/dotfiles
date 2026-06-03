{ pkgs, ... }:

{
  imports = [
    ./components/asus-laptop.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/niri.nix
    ./components/power-management.nix
    ./components/thunar.nix
  ];

  programs = {
    obs-studio.enable = true;
    localsend.enable = true;
  };

  myOptions = {
    dms.source = "git";
    quickshell.source = "git";
  };

  environment.systemPackages = with pkgs; [
    obsidian
    vscodium
    moonlight-qt
  ];
}