{ ... }:

{
  networking.hostName = "bedroompc";

  imports = [
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];
}