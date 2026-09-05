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

      # greetd runs initial_session exactly once per boot, so it is the cold
      # boot that the Plymouth LUKS prompt already authenticated: straight to
      # the desktop. Every session after it - every logout - comes through
      # default_session, which asks niri to bring the session up locked.
      # See scripts/niri_lock-at-startup.sh.
      initial_session = {
        command = "niri-session";
        user = username;
      };

      default_session = {
        command = "NIRI_LOCK_AT_STARTUP=1 niri-session";
        user = username;
      };
    };
  };

  programs.hyprlock.enable = true;
  #security.pam.services.hyprlock.enableGnomeKeyring = true;
}