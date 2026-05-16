{ config, lib, ... }:

{
  networking.hostName = "taylorpc";

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  imports = [
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/laptop.nix
  ];
}