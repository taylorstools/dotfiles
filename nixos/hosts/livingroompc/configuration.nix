{ ... }:

{
  imports = [
    ../../modules/components/clevis-tang.nix
    ../../modules/components/nightly-reboot.nix
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "livingroompc";

  myOptions.nvidia.mode = "proprietary";

  #region network-bound LUKS unlock
  # Clevis has to reach the Tang server from the initrd, so the onboard Intel
  # NIC's driver has to be there too. Set here rather than in
  # hardware-configuration.nix, which nixos-generate-config overwrites.
  boot.initrd.availableKernelModules = [ "e1000e" ];

  myOptions.clevisTang.enable = true;
  #endregion
}
