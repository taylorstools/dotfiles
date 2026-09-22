{ config, lib, ... }:

let
  cfg = config.myOptions.clevisTang;
in
{
  options.myOptions.clevisTang = {
    enable = lib.mkEnableOption "network-bound LUKS unlock via Clevis and a Tang server";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "en* eth*";
      description = ''
        systemd-networkd Name= match for the NIC that has to come up in the
        initrd. The driver for it must also be in
        boot.initrd.availableKernelModules on the host.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    #region initrd networking
    # Clevis needs an address before cryptsetup runs. This also flips
    # boot.initrd.systemd.network.enable, which defaults to it.
    boot.initrd.network.enable = true;

    boot.initrd.systemd.network.networks."10-lan" = {
      matchConfig.Name = cfg.interface;
      networkConfig.DHCP = "ipv4";
      linkConfig.RequiredForOnline = "routable";
    };

    # wait-online blocks on every managed link by default, and the onboard
    # eno1 matches the glob above without ever having a cable in it - so it
    # sat out its full 120s timeout before clevis got a turn. One online
    # interface is enough, and a shorter timeout means a genuinely offline
    # boot reaches the passphrase prompt sooner.
    boot.initrd.systemd.network.wait-online = {
      anyInterface = true;
      timeout = 45;
    };
    #endregion

    #region clevis
    # Reads the Clevis token bound into the LUKS header by `clevis luks bind`,
    # so there is no JWE file to keep out of git or off the ESP. It runs
    # alongside the interactive prompt rather than replacing it: an
    # unreachable Tang server degrades to typing the passphrase instead of
    # failing the boot.
    boot.initrd.clevisLuksAskpass = {
      enable = true;
      useTang = true;
    };
    #endregion
  };
}
