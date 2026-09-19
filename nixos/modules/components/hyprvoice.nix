{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.hyprvoice;

  modelsDir = "%h/.local/share/hyprvoice/models/whisper";

  # ggml weights, named as internal/models/whisper expects to find them.
  # Fetched into the store instead of by `hyprvoice model download`, so a new
  # machine has its model the moment it finishes rebuilding. config.toml is
  # chezmoi-managed like the rest of ~/.config, and stays writable by
  # `hyprvoice configure`.
  modelRules = lib.mapAttrsToList (
    id: hash:
    "L+ ${modelsDir}/ggml-${id}.bin - - - - ${
      pkgs.fetchurl {
        name = "ggml-${id}.bin";
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${id}.bin";
        inherit hash;
      }
    }"
  ) cfg.models;
in
{
  options.myOptions.hyprvoice = {
    enable = lib.mkEnableOption "hyprvoice dictation daemon";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.myOptions.user.name;
      defaultText = lib.literalExpression "config.myOptions.user.name";
      description = "User whose graphical session runs the daemon.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/hyprvoice/package.nix { };
      defaultText = lib.literalExpression
        "pkgs.callPackage ../../pkgs/hyprvoice/package.nix { }";
      description = ''
        The hyprvoice package to use. Built with callPackage rather than
        injected through an overlay, for the same reason as roland: setting
        nixpkgs.overlays from inside a module's config makes pkgs depend on
        config, which is an infinite-recursion trap.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "medium.en" = "sha256-AAAA...";
      };
      description = ''
        Whisper models to place in ${modelsDir}, as model id mapped to the SRI
        hash of its ggml file. Get the hash of one already downloaded with
        `nix hash file --sri <path>`, or of one you don't have yet with
        `nix store prefetch-file <url>`.

        Only needed for the local whisper-cpp provider; cloud providers ignore
        this. The model named here must match `transcription.model` in the
        chezmoi-managed config.toml.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # One binary for everything: `hyprvoice toggle` from a niri bind,
    # `hyprvoice configure` to change settings, `hyprvoice status` to debug.
    # The subcommands talk to the daemon over ~/.cache/hyprvoice/control.sock.
    environment.systemPackages = [ cfg.package ];

    systemd.user.tmpfiles.users.${cfg.user}.rules = [
      "d %h/.local/share/hyprvoice 0755 - - -"
      "d ${modelsDir} 0755 - - -"
    ] ++ modelRules;

    systemd.user.services.hyprvoice = {
      description = "hyprvoice dictation daemon";
      documentation = [ "https://github.com/leonardotrapani/hyprvoice" ];

      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" "pipewire.service" ];
      wantedBy = [ "graphical-session.target" ];

      # environment.variables reaches login shells, not the user manager, so
      # the ydotool backend would look for its socket at the compiled-in
      # default and fail over to wtype without saying why.
      environment = lib.optionalAttrs config.programs.ydotool.enable {
        YDOTOOL_SOCKET = config.environment.variables.YDOTOOL_SOCKET;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} serve";

        # pw-record, whisper-cli, wtype and notify-send are on the package's
        # own PATH via its wrapper, so nothing is added here.
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
