{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.whisrs;
  system = pkgs.stdenv.hostPlatform.system;

  basePkg = inputs.whisrs.packages.${system}.default;

  # whisper.cpp links its backend at build time - there is no runtime switch -
  # so GPU decode means rebuilding whisrs with the cargo feature, the same
  # tradeoff as nixpkgs whisper-cpp's vulkanSupport.
  #
  # buildRustPackage maps buildFeatures -> cargoBuildFeatures inside the
  # function, so an overrideAttrs has to set the latter: the former is never
  # read back off the final derivation.
  whisrsPkg =
    if cfg.vulkan then
      basePkg.overrideAttrs (old: {
        cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "vulkan" ];
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.shaderc ];
        buildInputs = (old.buildInputs or [ ]) ++ (with pkgs; [
          vulkan-headers
          vulkan-loader
        ]);
      })
    else
      basePkg;

  # The pill's waveform (dot_config/DankMaterialShell/plugins/WhisrsPill): a
  # second capture of the same source whisrs records from. cava needs a config
  # file and a named source, and a QML plugin has no business writing either -
  # bars here must match barCount in WhisrsDaemon.qml.
  cavaHelper = pkgs.writeShellApplication {
    name = "whisrs-pill-cava";
    runtimeInputs = with pkgs; [
      cava
      pulseaudio
      coreutils
    ];
    text = ''
      conf="''${XDG_RUNTIME_DIR:-/tmp}/whisrs-pill-cava.conf"

      # cava's own `source = auto` resolves to the default SINK monitor, which
      # would draw whatever is playing instead of your voice.
      source_name="$(pactl get-default-source 2>/dev/null || true)"
      [ -n "$source_name" ] || source_name="auto"

      cat > "$conf" <<CONF
      [general]
      framerate = 30
      bars = 12
      autosens = 1

      [input]
      method = pulse
      source = $source_name

      [output]
      method = raw
      raw_target = /dev/stdout
      data_format = ascii
      ascii_max_range = 100
      channels = mono
      mono_option = average

      [smoothing]
      noise_reduction = 30
      CONF

      exec cava -p "$conf"
    '';
  };

  modelsDir = "%h/.local/share/whisrs/models";

  # ggml weights, named and placed exactly as `whisrs setup` would, so the
  # model_path in the chezmoi-managed config.toml resolves on a fresh machine
  # without anyone running setup. Same URL setup downloads from.
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
  options.myOptions.whisrs = {
    enable = lib.mkEnableOption "whisrs dictation daemon";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.myOptions.user.name;
      defaultText = lib.literalExpression "config.myOptions.user.name";
      description = "User whose session runs whisrsd, and who gets device access.";
    };

    vulkan = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Build the bundled whisper.cpp with its Vulkan backend for the 890M.
        Turn off to fall back to CPU if the shader build breaks on a bump -
        upstream's flake builds CPU-only, so this override is ours to keep
        working.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = whisrsPkg;
      defaultText = lib.literalExpression "inputs.whisrs.packages.\${system}.default";
      description = "The whisrs package to use. Upstream ships the flake; we only pick features.";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "small.en" = "sha256-AAAA...";
      };
      description = ''
        Whisper models to place in ~/.local/share/whisrs/models, as model id
        mapped to the SRI hash of its ggml file. Get the hash of one already
        downloaded with `nix hash file --sri <path>`, or of one you do not have
        yet with `nix store prefetch-file <url>`. The one named by model_path
        in config.toml has to be in here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # whisrs (CLI) and whisrsd (daemon). `whisrs setup` writes the initial
    # ~/.config/whisrs/config.toml; chezmoi owns it from there.
    environment.systemPackages = [ cfg.package cavaHelper ];

    # The model config.toml points at, so a fresh machine needs no setup run.
    systemd.user.tmpfiles.users.${cfg.user}.rules = [
      "d %h/.local/share/whisrs 0755 - - -"
      "d ${modelsDir} 0755 - - -"
    ] ++ modelRules;

    # whisrs can take its hotkeys straight off evdev ([hotkeys] in its config)
    # before XKB translation, without a niri bind - and that is exactly
    # why it needs to read the input devices and write to /dev/uinput. The
    # rule ships in the package; upstream's flake already rewrote its ACL
    # fallback to the store setfacl.
    services.udev.packages = [ cfg.package ];
    hardware.uinput.enable = true;
    users.users.${cfg.user}.extraGroups = [ "input" "uinput" ];

    systemd.user.services.whisrs = {
      description = "whisrs dictation daemon";
      documentation = [ "https://github.com/y0sif/whisrs" ];

      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" "pipewire.service" ];
      wantedBy = [ "graphical-session.target" ];

      # NixOS user units get a minimal PATH, not /run/current-system/sw/bin.
      # whisrsd shells out to `niri msg --json focused-window` for window
      # tracking (and logs a misleading "is Niri running?" when it cannot
      # find the binary), and its [hooks] run through `sh -c` in this same
      # environment - the pill's `dms ipc call whisrs ...` hooks need dms on
      # PATH. The system profile covers both, and whatever hooks come later.
      path = [ "/run/current-system/sw" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/whisrsd";

        # Upstream's own unit passes these through so window tracking works;
        # niri-session puts them in the user manager's environment.
        PassEnvironment = "NIRI_SOCKET WAYLAND_DISPLAY DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_RUNTIME_DIR";

        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
