{ pkgs, ... }:

let
  # One set of numbers for both the Plymouth theme and the niri splash: the
  # logo sits in the same place in each, so the handoff between them does
  # not move it. Change them in the shared file, not in either package --
  # htpc.nix draws the same mark from it.
  splashLogo = import ./components/assets/splash-logo.nix;
in
{
  imports = [
    ./components/claude-desktop.nix
    ./components/davinci-resolve.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/howdy.nix
    ./components/niri.nix
    ./components/niri-splash
    ./components/power-management.nix
    ./components/roland.nix
    ./components/thunar.nix
    ./components/whisrs.nix
  ];

  programs = {
    direnv.enable = true;
    localsend.enable = true;
    nix-ld.enable = true;
    obs-studio.enable = true;
  };

  myOptions = {
    claude-desktop = {
      enable = true;
      passwordStore = "gnome-libsecret";
    };

    dms.source = "stable";

    quickshell.source = "stable";

    whisrs.enable = true;

    niri-splash = {
      enable = true;
      # The dock is a separate DMS surface and comes up a second or two
      # after the bar; hold the splash for it too.
      namespaces = [ "dms:bar" "dms:dock" ];
    } // splashLogo;
    
    plymouth = {
      enable = true;
      theme = "minimal";
      themePackages = [
        (pkgs.callPackage ../pkgs/plymouth-theme-minimal/package.nix splashLogo)
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    kdePackages.krdc
    moonlight-qt
    obsidian
    vscodium
  ];
}
