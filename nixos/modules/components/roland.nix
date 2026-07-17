{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.roland;
in
{
  options.myOptions.roland = {
    enable = lib.mkEnableOption "roland touch gesture recognizer";

    user = lib.mkOption {
      type = lib.types.str;
      default = "taylor";
      description = "User account that runs roland and gets added to the input group.";
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = "%E/roland/config.toml";
      example = "%E/roland/config.toml";
      description = ''
        Path passed to roland's --config flag. %E
        expands to $XDG_CONFIG_HOME for user units.
      '';
    };

    niriPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.niri;
      defaultText = lib.literalExpression "pkgs.niri";
      description = ''
        roland shells out to `niri msg -j outputs` at startup to read screen
        dimensions, and panics if that fails. If you get niri from niri-flake,
        set this to config.programs.niri.package so the versions match.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.roland;
      defaultText = lib.literalExpression "pkgs.roland";
      description = "The roland package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: _prev: {
        roland = final.callPackage ./pkgs/roland.nix { };
      })
    ];

    environment.systemPackages = [ cfg.package ];

    # roland opens evdev devices directly via libinput's udev seat
    users.users.${cfg.user}.extraGroups = [ "input" ];

    systemd.user.services.roland = {
      description = "Roland touch gesture recognizer";
      documentation = [ "https://github.com/oknozor/roland" ];

      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      # niri: needed at startup for `niri msg -j outputs`
      # bash/coreutils: gesture actions are run via `sh -c <action>`
      environment.PATH = lib.mkForce (
        lib.concatStringsSep ":" [
          (lib.makeBinPath [ cfg.niriPackage ])
          "/run/wrappers/bin"
          "/etc/profiles/per-user/${cfg.user}/bin"
          "/nix/var/nix/profiles/default/bin"
          "/run/current-system/sw/bin"
        ]
      );

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} --config ${cfg.configFile}";

        # niri may not be up yet on first try; roland unwraps and dies if so
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}