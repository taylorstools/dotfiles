{ config, lib, pkgs, inputs, ... }:

# dux-greeter (formerly dank-greeter) as greetd's login screen, styled after
# dot_config/hypr/hyprlock.conf: date and clock up top, password pill in the
# lower third, battery bottom-left, power bottom-right, over the same
# pre-blurred effects wallpaper hyprlock uses.
#
# settings.json and session.json here are the greeter's whole config: they
# are not the DMS ones, so Settings -> Greeter in the shell does not touch
# them. Preview edits in the running session with
# scripts/dux-greeter-preview.sh before rebuilding.

let
  cfg = config.myOptions.duxGreeter;
  username = config.myOptions.user.name;
  home = config.users.users.${username}.home;

  # The wallpaper path has to be absolute: greetd's preStart copies it into
  # the greeter's data dir as root, and a ~ would resolve against the greeter
  # user, not this one.
  settings = lib.importJSON ./settings.json // {
    lockScreenWallpaperPath = "${home}/.config/.EffectsWallpaper.png";
  };

  # The upstream module copies each configFiles entry with `cp "$f" .`, so
  # the basename is the name the greeter reads. A bare store path would land
  # as <hash>-settings.json; linkFarm keeps the plain names.
  greeterConfig = pkgs.linkFarm "dux-greeter-config" [
    { name = "settings.json"; path = pkgs.writeText "settings.json" (builtins.toJSON settings); }
    { name = "session.json"; path = ./session.json; }
  ];
in
{
  imports = [ inputs.dux-greeter.nixosModules.default ];

  options.myOptions.duxGreeter = {
    enable = lib.mkEnableOption "dux-greeter as the greetd login screen";
  };

  config = lib.mkIf cfg.enable {
    programs.dms-greeter = {
      enable = true;
      compositor.name = "niri";

      # No configHome: that would copy the live DMS settings.json over this
      # one. Colors still come from the live matugen output, so the theme
      # follows the wallpaper; later entries win, so the DMS 2.0 path is last.
      configFiles = [
        "${greeterConfig}/settings.json"
        "${greeterConfig}/session.json"
        "${home}/.cache/DankMaterialShell/dms-colors.json"
        "${home}/.cache/dms/dms-colors.json"
      ];
    };

    # greetd.nix drops its own default_session (niri brought up locked) when
    # this is on, so the greeter module's command takes the slot. The cold
    # boot initial_session autologin is unchanged.
    services.greetd.settings.default_session.user = "greeter";
    users.users.greeter = {
      isSystemUser = true;
      group = "greeter";
    };
    users.groups.greeter = { };

    # Read by scripts/niri_lock-at-startup.sh: every session after the cold
    # boot now came through the greeter's password prompt, so locking it on
    # arrival would ask for the password twice.
    environment.etc."greetd/greeter-authenticates".text = "";
  };
}
