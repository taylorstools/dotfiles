{ ... }:

{
  networking.hostName = "livingroompc";

  # NVIDIA driver
  myOptions.nvidia.mode = "proprietary";

  imports = [
    ../../modules/components/nightly-reboot.nix
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];
}