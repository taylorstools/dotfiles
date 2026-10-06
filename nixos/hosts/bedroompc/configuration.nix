{ ... }:

{
  imports = [
    ../../modules/components/clevis-tang.nix
    ../../modules/components/initrd-wifi.nix
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "bedroompc";

  myOptions.intel.mode = "modern";

  # The Intel GOP hands the initrd native 3840x2160, where livingroompc's
  # nvidia box drops to 1920x1080 before the kernel starts. The splash bitmaps
  # are fixed pixel sizes, so matching livingroompc's apparent size takes
  # twice its scale (the htpc.nix default of 1.5).
  myOptions.htpc.splashScale = 3.0;

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

  myOptions.initrdWifi = {
    enable = true;
    interface = "wlp0s20f3";
    credentialFile = ./initrd-wifi.cred;
  };

  myOptions.clevisTang = {
    enable = true;
    interface = "wlp0s20f3";
  };
}
