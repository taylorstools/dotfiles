{ config, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/laptop.nix
  ];
}
