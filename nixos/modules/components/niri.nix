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
      # niri-session calls `systemctl --user import-environment` and
      # `dbus-update-activation-environment --all` with no variable list, which
      # systemd deprecated - it prints a warning at every login and logout.
      # Spell the names out at runtime: identical behaviour, no warning.
      # Drop once https://github.com/YaLTeR/niri/issues/254 lands upstream.
      niri = prev.niri.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          substituteInPlace $out/bin/niri-session \
            --replace-fail \
              'systemctl --user import-environment' \
              'systemctl --user import-environment $(env | sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p")' \
            --replace-fail \
              'dbus-update-activation-environment --all' \
              'dbus-update-activation-environment $(env | sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p")'
        '';
      });

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