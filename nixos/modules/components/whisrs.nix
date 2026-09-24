{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.whisrs;
  system = pkgs.stdenv.hostPlatform.system;

  basePkg = inputs.whisrs.packages.${system}.default;

  # whisper.cpp links its backend at build time - there is no runtime switch -
  # so GPU decode means rebuilding whisrs with the cargo feature, the same
  # tradeoff as whisper-cpp's vulkanSupport in the hyprvoice package.
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
  };

  config = lib.mkIf cfg.enable {
    # whisrs (CLI) and whisrsd (daemon). `whisrs setup` writes the initial
    # ~/.config/whisrs/config.toml - chezmoi can take it over afterwards, the
    # same way it owns hyprvoice's.
    environment.systemPackages = [ cfg.package cavaHelper ];

    # Unlike hyprvoice and Handy, whisrs takes its hotkeys straight off evdev
    # before XKB translation, so there is no niri bind - and that is exactly
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
