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

  environment.systemPackages = with pkgs; [
    brightnessctl
    fd
    fzf
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
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    xed-editor
    xsettingsd
    xwayland-satellite
    yad
  ];
}