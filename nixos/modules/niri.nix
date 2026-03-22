{ config, pkgs, lib, ... }:

{
  services = {
    gnome.gnome-keyring = {
      enable = true;
    };

    greetd = {
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

    tumbler.enable = true;
    keyd = {
      enable = true;
      keyboards = {

        default = {
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

  security = {
    pam.services.greetd.enableGnomeKeyring = true;
  };

  programs = {
    niri.enable = true;
    thunar.enable = true;

    dms-shell = {
      enable = true;

      systemd = {
        enable = true;
        restartIfChanged = true;
      };
      
      enableDynamicTheming = true;
      enableClipboardPaste = true;
    };
  };

  environment.systemPackages = with pkgs; [
    adw-gtk3
    brightnessctl
    fd
    fzf
    hypridle
    hyprlock
    keyd
    nwg-look
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
}