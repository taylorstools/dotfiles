{ pkgs, ... }:

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

  environment.systemPackages = with pkgs; [
    brightnessctl
    fd
    fzf
    ghostty
    gnome-calculator
    gparted
    grim
    gsettings-desktop-schemas
    hypridle
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