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
    obs-studio.enable = true;
    localsend.enable = true;
  };

  myOptions = {
    claude-desktop.enable = true;
    dms.source = "stable";
    quickshell.source = "stable";
  };

  environment.systemPackages = with pkgs; [
    kdePackages.krdc
    obsidian
    vscodium
    # Moonlight fails to build with ffmpeg 9
    (moonlight-qt.override { ffmpeg = ffmpeg_8; })
  ];
}