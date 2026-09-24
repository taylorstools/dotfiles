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
    environment.systemPackages = [ cfg.package ];

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
