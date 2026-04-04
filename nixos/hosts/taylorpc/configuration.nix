{ config, pkgs, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ./luks-tpm-autounlock.nix
    ../../modules/secure-boot.nix
    ../../modules/niri.nix
  ];
}