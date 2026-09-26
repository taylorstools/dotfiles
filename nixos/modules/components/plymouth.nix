{ config, lib, utils, ... }:

let
  cfg = config.myOptions.plymouth;

  cryptsetupUnits = map
    (name: "systemd-cryptsetup@${utils.escapeSystemdPath name}.service")
    (lib.attrNames config.boot.initrd.luks.devices);
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

    # The theme has to know the moment the root volume opens, and Plymouth has
    # no callback for it. When clevis or the TPM answers instead of a person,
    # the password callbacks just stop; root-mounted does arrive, but only from
    # plymouth-switch-root.service right before switch-root, which is too late
    # to be useful. So the initrd says it outright, once every LUKS device is
    # open. minimal.script picks the status up in update_status(); the string
    # is shared with it.
    boot.initrd.systemd.services.plymouth-luks-unlocked =
      lib.mkIf (cryptsetupUnits != [ ]) {
        description = "Tell Plymouth the LUKS volumes are open";
        wantedBy = [ "cryptsetup.target" ];
        requires = cryptsetupUnits;
        after = cryptsetupUnits;
        # Default dependencies would order this after sysinit.target, which
        # itself waits for cryptsetup.target: a cycle.
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          # The leading "-": a splash that is not running must never fail the
          # boot. The client binary is already in the initrd, via the upstream
          # module's extraBin.plymouth.
          ExecStart = "-${lib.getExe' config.boot.plymouth.package "plymouth"} update --status=luks-unlocked";
        };
      };

    boot.initrd.verbose = !cfg.quietBoot;
    boot.consoleLogLevel = lib.mkIf cfg.quietBoot 0;
  };
}