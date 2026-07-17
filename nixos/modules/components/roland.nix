.dotfiles/nixos/modules/components/pkgs{
  config,
  lib,
  pkgs,
  ...
}:

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
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./roland-config.toml";
      description = ''
        Config file passed to roland via --config. When null, roland is started
        without the flag and falls back to its own default lookup
        (~/.config/roland/config.toml), which is the right choice if you manage
        that file with chezmoi or home-manager.
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

    # roland reads evdev devices directly out of /dev/input
    users.users.${cfg.user}.extraGroups = [ "input" ];

    systemd.user.services.roland = {
      description = "Roland touch gesture recognizer";
      documentation = [ "https://github.com/oknozor/roland" ];

      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart =
          "${lib.getExe cfg.package}"
          + lib.optionalString (cfg.configFile != null) " --config ${cfg.configFile}";
        Restart = "on-failure";
        RestartSec = 2;

        # roland needs /dev/input and libinput/udev; it does not need much else
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}