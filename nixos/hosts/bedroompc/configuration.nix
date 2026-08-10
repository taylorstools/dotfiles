{ ... }:

{
  imports = [
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "bedroompc";

  myOptions.intel.mode = "modern";
}