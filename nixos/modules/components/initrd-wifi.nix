{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.initrdWifi;

  wpaSupplicant = "${pkgs.wpa_supplicant}/bin/wpa_supplicant";
  credential = "${cfg.credentialFile}";
  device = "sys-subsystem-net-devices-${cfg.interface}.device";
in
{
  options.myOptions.initrdWifi = {
    enable = lib.mkEnableOption "joining wifi from the systemd initrd, before the root volume is unlocked";

    interface = lib.mkOption {
      type = lib.types.str;
      example = "wlp0s20f3";
      description = ''
        Name of the wireless interface as `ip link` shows it once booted. Not
        a glob: wpa_supplicant drives exactly one interface, and its unit is
        bound to that interface's device.
      '';
    };

    credentialFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        A wpa_supplicant.conf sealed to this machine's TPM:

          systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs=7 \
            --name=wpa_supplicant.conf <plaintext> <this file>

        Only this TPM can open it, and only while PCR 7 (Secure Boot state
        and the keys that verified the boot) matches what it was sealed
        against. That is what makes it safe to keep in git and copy into the
        store and the signed initrd as-is.

        scripts/luks-clevis-autounlock.sh seals it into
        /etc/nixos/initrd-wifi.cred, which the update alias and nixos-upgrade
        copy to hosts/<host>/initrd-wifi.cred before every rebuild, like
        hardware-configuration.nix. Hosts point this option at that copy.
      '';
    };

    frequencies = lib.mkOption {
      type = lib.types.listOf lib.types.ints.positive;
      default = [ ];
      example = lib.literalExpression "lib.genList (n: 5955 + 20 * n) 59  # every 6 GHz channel";
      description = ''
        Frequencies (MHz) the initrd may connect on; empty means any. For a
        radio the card associates with but never finishes the handshake on,
        which wpa_supplicant otherwise retries before moving on. Scanning
        still covers every band: the card only enables its 6 GHz channels
        after a 2.4/5 GHz scan has told it the country.

        The build does not read this. It is part of the sealed credential,
        so luks-clevis-autounlock.sh writes it in and re-seals when it
        changes; run --enable after editing it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable && config.boot.initrd.systemd.tpm2.enable;
        message = "myOptions.initrdWifi needs the systemd initrd with TPM2 support to open its credential.";
      }
    ];

    #region driver support
    # mac80211 sets up its pairwise and management-frame keys through the
    # kernel crypto API even when the card does the crypto itself, and those
    # algorithms are requested at runtime rather than declared as module
    # dependencies, so the module closure would not pull them in on its own.
    # The NIC driver and its firmware are per host.
    boot.initrd.availableKernelModules = [ "ccm" "ctr" "cmac" "gcm" ];

    # cfg80211 reads the regulatory database when it loads; without it the
    # initrd sits in the restrictive world domain.
    boot.initrd.extraFirmwarePaths = [ "regulatory.db" "regulatory.db.p7s" ];
    #endregion

    #region wpa_supplicant
    # No NetworkManager in the initrd, so wpa_supplicant associates and the
    # systemd-networkd config from clevis-tang.nix (or whatever else wants
    # the network) takes the link from there once it has carrier.
    #
    # The config only ever exists decrypted under the unit's credentials
    # directory, which systemd keeps in memory and tears down with the unit.
    # If the TPM refuses (PCR 7 moved after a dbx or key change), the unit
    # fails, nothing comes online, and boot falls through to the passphrase
    # prompt. Re-seal from the running system afterwards.
    boot.initrd.systemd.storePaths = [ wpaSupplicant credential ];

    boot.initrd.systemd.services.initrd-wpa-supplicant = {
      description = "WPA supplicant on ${cfg.interface} (initrd)";
      wantedBy = [ "initrd.target" ];
      bindsTo = [ device ];
      wants = [ "tpm2.target" ];
      after = [ device "tpm2.target" ];

      # Hand the card back disassociated before switch-root, so
      # NetworkManager starts stage 2 from a clean slate.
      conflicts = [ "initrd-switch-root.target" "shutdown.target" ];
      before = [ "initrd-switch-root.target" "shutdown.target" ];
      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        LoadCredentialEncrypted = "wpa_supplicant.conf:${credential}";
        ExecStart = "${wpaSupplicant} -D nl80211 -i ${cfg.interface} -c %d/wpa_supplicant.conf";
      };
    };
    #endregion
  };
}
