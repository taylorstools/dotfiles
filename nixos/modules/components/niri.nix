{ config, pkgs, ... }:

{
  services.gnome.gnome-keyring.enable = true;

  programs.niri.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    fd
    fzf
    gparted
    hypridle
    loupe
    nwg-look
    python3
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