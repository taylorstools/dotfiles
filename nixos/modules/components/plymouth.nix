{ config, lib, ... }:

let
  cfg = config.myOptions.plymouth;
in
{
  options.myOptions.plymouth = {
    enable = lib.mkEnableOption
      "Plymouth boot splash, including the graphical LUKS passphrase prompt";

    theme = lib.mkOption {
      type = lib.types.str;
      default = "bgrt";
      description = ''
        Plymouth theme name. "bgrt" reuses the firmware/OEM logo published in
        the ACPI BGRT table with a spinner and the password field beneath it,
        so the handoff from firmware to initrd has no visible seam.
        "spinner" is the same animation with no logo. Any other value has to
        be supplied by myOptions.plymouth.themePackages.
      '';
    };

    themePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.adi1090x-plymouth-themes ]";
      description = "Extra packages searched for the theme named above.";
    };

    quietBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Silence kernel, udev and systemd console output so log lines do not
        overdraw the splash. Set to false while debugging a boot problem;
        Esc still reveals the log at runtime either way.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      inherit (cfg) theme themePackages;
    };

    # The agent that draws the passphrase prompt on top of the splash is a
    # systemd password agent, so the initrd has to be the systemd one.
    boot.initrd.systemd.enable = lib.mkDefault true;

    # The upstream plymouth module already adds "splash" itself.
    boot.kernelParams = lib.optionals cfg.quietBoot [
      "quiet"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    boot.initrd.verbose = !cfg.quietBoot;
    boot.consoleLogLevel = lib.mkIf cfg.quietBoot 0;
  };
}