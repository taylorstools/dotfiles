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

    # niri-session is not a real greeter: it runs a desktop and exits rather
    # than creating a session over greetd's IPC socket, so greetd calls that
    # "greeter exited without creating a session" and terminates. Without a
    # restart that leaves nothing driving the display - a black screen on the
    # second logout of any boot. The module defaults this to false whenever
    # initial_session is set; greetd's runfile in /run is what stops the
    # autologin repeating, and it outlives a service restart, so a restarted
    # greetd goes to default_session and the session comes up locked.
    restart = true;

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
        # greetd runs the command as `exec <command>`, so the variable has
        # to be set by env(1) rather than as an assignment prefix.
        command = "env NIRI_LOCK_AT_STARTUP=1 niri-session";
        user = username;
      };
    };
  };

  programs.hyprlock.enable = true;
  #security.pam.services.hyprlock.enableGnomeKeyring = true;
}