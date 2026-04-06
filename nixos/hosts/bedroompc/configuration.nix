{ config, pkgs, ... }:

{
  networking.hostName = "bedroompc";

  imports = [
    #./luks-tpm-autounlock.nix
    ../../modules/htpc.nix
  ];
}