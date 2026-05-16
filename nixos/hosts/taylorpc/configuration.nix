{ config, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/laptop.nix
  ];
}
