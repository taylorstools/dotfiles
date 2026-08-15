{ pkgs, lib, ... }:

{
  imports = [
    ./keyd.nix
  ];

  programs.niri.enable = true;
  programs.dconf.enable = true;

  services.gnome.gnome-keyring.enable = true;

  systemd.packages = [ pkgs.libinput-gestures ];

  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.common.default = "gtk";
  };

  nixpkgs.overlays = [
    (final: prev: {
      # xwayland-satellite 0.8.2 stops surfacing modal transients whose parent
      # is an unmapped 1x1 window (DaVinci Resolve's Project Manager).
      # Pinned to 0.8.1 until upstream fixes it.
      xwayland-satellite = prev.xwayland-satellite.overrideAttrs (old: rec {
        version = "0.8.1";
        src = prev.fetchFromGitHub {
          owner = "Supreeeme";
          repo = "xwayland-satellite";
          rev = "v${version}";
          hash = "sha256-BUE41HjLIGPjq3U8VXPjf8asH8GaMI7FYdgrIHKFMXA=";
        };
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          inherit src;
          hash = "sha256-16L6gsvze+m7XCJlOA1lsPNELE3D364ef2FTdkh0rVY=";
        };
      });
    })
  ];

  environment.systemPackages = with pkgs; [
    brightnessctl
    fd
    fzf
    ghostty
    gnome-calculator
    gparted
    grim
    gsettings-desktop-schemas
    loupe
    nwg-look
    python3
    satty
    showtime
    slurp
    wlogout
    wlr-which-key
    xed-editor
    xsettingsd
    xwayland-satellite
    yad
  ];
}