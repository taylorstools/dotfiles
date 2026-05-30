{ ... }:

{
  networking.hostName = "livingroompc";

  # NVIDIA driver
  myOptions.nvidia.mode = "proprietary";

  imports = [
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/htpc.nix
  ];
}