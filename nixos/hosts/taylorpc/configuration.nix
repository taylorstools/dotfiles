{ config, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ./luks-tpm-autounlock.nix
    ../../modules/laptop.nix
  ];
}
