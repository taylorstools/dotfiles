{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.niri-splash;

  splash = pkgs.callPackage ./package.nix { };

  # Rasterised at 2x and scaled down when drawn: crisp on a HiDPI output
  # without the splash loading an SVG renderer at startup.
  logoPng = pkgs.runCommand "niri-splash-logo.png"
    { nativeBuildInputs = [ pkgs.librsvg ]; }
    "rsvg-convert -w ${toString (builtins.floor (cfg.logoWidth * 2))} ${cfg.logo} -o $out";

  # The two states of the cursor include niri reads last (see config.kdl).
  # The rest line is byte-identical to the chezmoi-managed copy and to what
  # niri-splash.py writes, so every writer converges on the same file.
  cursorFile = ".config/niri/custom/cursor-startup.kdl";
  cursorRest = "// niri-splash: no cursor override active";
  cursorBlank = ''
    // niri-splash: written at login, restored when the splash lifts.
    cursor {
        xcursor-theme "niri-splash-blank"
    }
  '';
  restoreCursor = pkgs.writeShellScript "niri-splash-restore-cursor" ''
    f="$HOME/${cursorFile}"
    if [ -f "$f" ] && grep -q 'niri-splash-blank' "$f"; then
      printf '%s\n' '${cursorRest}' > "$f"
    fi
  '';
  blankCursor = pkgs.writeShellScript "niri-splash-blank-cursor" ''
    f="$HOME/${cursorFile}"
    [ -d "$(dirname "$f")" ] || exit 0
    printf '%s' ${lib.escapeShellArg cursorBlank} > "$f"
  '';

  flags = lib.escapeShellArgs (
    lib.concatMap (n: [ "--namespace" n ]) cfg.namespaces
    ++ [
      "--niri" (lib.getExe' cfg.niriPackage "niri")
      "--fade-ms" (toString cfg.fadeMs)
      "--slot-height" (toString cfg.slotHeight)
      "--background" cfg.background
      "--foreground" cfg.foreground
    ]
    ++ lib.optionals (cfg.logo != null) [
      "--logo" "${logoPng}"
      "--logo-width" (toString cfg.logoWidth)
      "--logo-gap" (toString cfg.logoGap)
    ]
  );
in
{
  options.myOptions.niri-splash = {
    enable = lib.mkEnableOption "the niri startup splash";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.myOptions.user.name;
      defaultText = lib.literalExpression "config.myOptions.user.name";
      description = "User whose ~/.icons gets the blank cursor theme.";
    };

    niriPackage = lib.mkOption {
      type = lib.types.package;
      default = config.programs.niri.package;
      defaultText = lib.literalExpression "config.programs.niri.package";
      description = "Must be the niri the session runs; `niri msg` is version-checked.";
    };

    namespaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "dms:bar" ];
      example = [ "dms:bar" "dms:dock" ];
      description = ''
        Layer-shell namespaces that must all exist before the splash lifts.
        Only list surfaces that always appear; a missing one costs 20s on
        every login.
      '';
    };

    fadeMs = lib.mkOption {
      type = lib.types.numbers.positive;
      default = 500;
      description = "Fade-out duration.";
    };

    logo = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        SVG drawn above the spinner. Give plymouth-theme-minimal the same
        logo, logoWidth and logoGap and it holds still across the handoff.
      '';
    };
    logoWidth = lib.mkOption { type = lib.types.numbers.positive; default = 112; };
    logoGap = lib.mkOption { type = lib.types.numbers.nonnegative; default = 60; };

    slotHeight = lib.mkOption {
      type = lib.types.numbers.positive;
      default = 42;
      description = ''
        The Plymouth theme's fieldHeight. Logo, gap and a slot this tall are
        centred as one block; the spinner is centred in the slot where
        Plymouth's passphrase field was.
      '';
    };

    background = lib.mkOption { type = lib.types.str; default = "#000000"; };
    foreground = lib.mkOption { type = lib.types.str; default = "#e6e6e6"; };
  };

  config = lib.mkIf cfg.enable {
    # On PATH for previews: niri-splash --hold-ms 3000
    environment.systemPackages = [ splash ];

    # niri resolves cursor themes from ~/.icons whatever its environment.
    systemd.user.tmpfiles.users.${cfg.user}.rules = [
      "L+ %h/.icons/niri-splash-blank - - - - ${splash}/share/icons/niri-splash-blank"
    ];

    systemd.user.services.niri-splash = {
      description = "Startup splash for the niri session";
      # Started with the user manager, before greetd runs niri-session, so
      # Python and GTK load while niri is still coming up; the program waits
      # for the display itself. niri.service is named for a second login of
      # a user manager that never went away. Deliberately no After=.
      wantedBy = [ "default.target" "niri.service" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe splash} ${flags}";
        # However the splash ended, the cursor must not stay blank.
        ExecStopPost = restoreCursor;
        Restart = "no";
        TimeoutStopSec = 5;
      };
    };

    # Writes the blank override at logout, so it is already in place before
    # niri reads its config at the next login. RemainAfterExit makes
    # ExecStop fire at session end for a unit with a trivial ExecStart.
    systemd.user.services.niri-splash-next-boot = {
      description = "Arrange a blank cursor for the next niri login";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = blankCursor;
      };
    };
  };
}