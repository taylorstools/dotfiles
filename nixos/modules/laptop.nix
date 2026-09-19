{ pkgs, ... }:

let
  # One set of numbers for both the Plymouth theme and the niri splash: the
  # logo sits in the same place in each, so the handoff between them does
  # not move it. Change them here, not in either package.
  splashLogo = {
    logo = ./components/assets/nixos-logo.svg;
    logoWidth = 112;
    logoGap = 60;
  };
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

      # Chromium's os_crypt autodetect reads XDG_CURRENT_DESKTOP to pick a
      # keyring backend. niri is neither GNOME nor KDE, so it falls through to
      # the plaintext "basic" store, safeStorage.isEncryptionAvailable() goes
      # false, and the app warns that the sign-in will not be saved. Name the
      # backend: services.gnome.gnome-keyring.enable in components/niri.nix
      # provides the secret service this points at.
      passwordStore = "gnome-libsecret";
    };

    dms.source = "stable";

    quickshell.source = "stable";

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