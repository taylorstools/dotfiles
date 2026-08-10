{ ... }:

{
  imports = [
    ../../modules/components/nightly-reboot.nix
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "livingroompc";

  myOptions.nvidia.mode = "proprietary";
}