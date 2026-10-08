{ lib, ... }:

{
  imports = [
    ../../modules/components/clevis-tang.nix
    ../../modules/components/initrd-wifi.nix
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
  ];

  networking.hostName = "bedroompc";

  myOptions.intel.mode = "modern";

  # Wifi makes the unlock slower and less even than livingroompc's cable:
  # the disk opens around 12-14s after power-on, which the default 15s hold
  # cut close enough that the passphrase field flashed up just before it.
  myOptions.htpc.passwordRevealSeconds = 25;

  # bedroompc has no cable, so Clevis reaches Tang over wifi from the initrd.
  # iwlwifi only declares the newest firmware API it supports, which
  # linux-firmware does not always ship, so the version it actually loads
  # (dmesg: "loaded firmware version ... so-a0-gf-a0-89.ucode") is named
  # explicitly. If a firmware update moves that number and this file
  # disappears, the initrd has no wifi and boot falls back to the passphrase;
  # update the name from dmesg. Set here rather than in
  # hardware-configuration.nix, which nixos-generate-config overwrites.
  boot.initrd.availableKernelModules = [ "iwlwifi" "iwlmvm" ];
  boot.initrd.extraFirmwarePaths = [
    "iwlwifi-so-a0-gf-a0-89.ucode"
    "iwlwifi-so-a0-gf-a0.pnvm"
  ];

  # The credential is per install: luks-clevis-autounlock.sh seals it to this
  # machine's TPM once Secure Boot keys are enrolled. Until it exists and is
  # tracked by git, the initrd simply has no wifi and boot falls back to the
  # passphrase, rather than the build failing on a missing file.
  myOptions.initrdWifi = {
    enable = builtins.pathExists ./initrd-wifi.cred;
    interface = "wlp0s20f3";
    credentialFile = ./initrd-wifi.cred;

    # 6 GHz only. The Archer's 5 GHz radio never accepts this AX211's reply to
    # the first handshake message (reason=15, WPA2 and WPA3 alike, Smart
    # Connect on or off, in stage 2 as well), and trying it first cost 8-17s
    # every boot. Remove this if 5 GHz is ever fixed, then run
    # luks-clevis-autounlock.sh --enable to re-seal.
    frequencies = lib.genList (n: 5955 + 20 * n) 59;
  };

  myOptions.clevisTang = {
    enable = true;
    interface = "wlp0s20f3";
  };
}
