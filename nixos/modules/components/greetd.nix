{ config, pkgs, lib, ... }:

let
  username = config.myOptions.user.name;
in
{
  imports = [
    #./ydotool.nix
  ];

  services.greetd = {
    enable = true;

    settings = {
      terminal = {
        vt = lib.mkForce 8;
      };

      initial_session = {
        command = "niri-session";
        user = username;
      };

      default_session = {
        command = "niri-session";
        user = username;
      };
    };
  };

  programs.hyprlock.enable = true;
  security.pam.services.hyprlock.enableGnomeKeyring = true;
}