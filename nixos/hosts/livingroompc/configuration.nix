{ config, ... }:

{
  networking.hostName = "livingroompc";

  imports = [
    ./luks-tpm-autounlock.nix
    ../../modules/htpc.nix
  ];
}