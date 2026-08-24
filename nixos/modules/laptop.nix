{ pkgs, ... }:

{
  imports = [
    ./components/claude-desktop.nix
    ./components/davinci-resolve.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/niri.nix
    ./components/power-management.nix
    ./components/roland.nix
    ./components/thunar.nix
  ];

  programs = {
    localsend.enable = true;
    nix-ld.enable = true;
    obs-studio.enable = true;
  };

  myOptions = {
    claude-desktop.enable = true;
    dms.source = "stable";
    quickshell.source = "stable";
  };

  environment.systemPackages = with pkgs; [
    kdePackages.krdc
    moonlight-qt
    obsidian
    vscodium
  ];
}