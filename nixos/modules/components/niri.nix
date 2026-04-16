{ config, pkgs, ... }:

{
  imports = [
    ./keyd.nix
  ];

  programs.niri.enable = true;

  services.gnome.gnome-keyring.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    fd
    fzf
    gparted
    grim
    hypridle
    libinput-gestures
    loupe
    nwg-look
    python3
    satty
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