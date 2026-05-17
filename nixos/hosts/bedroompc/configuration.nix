{ config, ... }:

{
  networking.hostName = "bedroompc";

  imports = [
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/htpc.nix
  ];
}