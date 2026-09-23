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

  # Clevis has to reach the Tang server from the initrd, so the NIC driver has
  # to be there too. The cable is in the ASIX USB adapter (enp0s20f0u7), not
  # the onboard eno1; e1000e is kept in case the cable ever moves. Set here
  # rather than in hardware-configuration.nix, which nixos-generate-config
  # overwrites.
  boot.initrd.availableKernelModules = [ "ax88179_178a" "e1000e" ];

  myOptions.clevisTang.enable = true;

  # The firmware hands the initrd a framebuffer that takes the theme's design
  # units as-is here, so no scaling.
  myOptions.htpc.splashScale = 1.0;
}