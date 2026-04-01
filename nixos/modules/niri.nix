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
    pam.services.login.enableGnomeKeyring = true;
    pam.services.greetd.enableGnomeKeyring = true;
    pam.services.greetd-password.enableGnomeKeyring = true;
  };
  services.dbus.packages = [ pkgs.gnome-keyring pkgs.gcr ];

  programs = {
    niri.enable = true;

    thunar = {
      enable = true;
      plugins = with pkgs; [
        thunar-archive-plugin
      ];
    };
    
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
    accountsservice
    adw-gtk3
    brightnessctl
    fd
    file-roller
    fzf
    gparted
    hypridle
    hyprlock
    keyd
    libsecret
    loupe
    nwg-look
    python3
    swaybg
    wlogout
    wlr-which-key
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    xed-editor
    xsettingsd
    xwayland-satellite
    yad
    ydotool
  ];

  systemd.user.services.ydotoold = {
    description = "ydotool daemon";

    serviceConfig = {
      ExecStart = "${pkgs.ydotool}/bin/ydotoold";

      Restart = "always";

      SupplementaryGroups = [ "input" ];
      DeviceAllow = [
        "/dev/uinput rw"
      ];
      PrivateDevices = false;
    };

    wantedBy = [ "default.target" ];
  };

  boot.kernelModules = [ "uinput" ];
}