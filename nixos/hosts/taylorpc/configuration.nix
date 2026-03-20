{ config, pkgs, lib, ... }:

{
  # Hostname
  networking.hostName = "taylorpc";

  services = {
    tumbler.enable = true;
    upower.enable = true;
    keyd = {
      enable = true;
      keyboards = {
        default = {
          # match all keyboards
          ids = [ "*" ];
          settings = {
            main = {
              leftmeta = "overload(meta, macro(leftmeta+d))";
            };
          };
          extraConfig = ''
            overload_tap_timeout = 150
          '';
        };
      };
    };
  };

  programs = {
    niri.enable = true;
    dms-shell.enable = true;
    thunar.enable = true;
  };

  systemd.user.services.niri-flake-polkit.enable = false;

  # Packages
  environment.systemPackages = with pkgs; [
    adw-gtk3
    brightnessctl
    fzf
    hypridle
    hyprlock
    keyd
    nwg-look
    polkit
    polkit_gnome
    swaybg
    thunar-archive-plugin
    wlogout
    wlr-which-key
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    xdg-user-dirs
    xwayland-satellite
    yad
  ];

  services.greetd = {
    enable = true;
    settings = {
      terminal = {
        vt = lib.mkForce 8;
       };
      initial_session = {
        command = "niri-session";
        user = "taylor";
      };
      default_session = {
        command = "niri-session";
        user = "taylor";
      };
    };
  };

  system.stateVersion = "25.11"; # Did you read the comment?
}