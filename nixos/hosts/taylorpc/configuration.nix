{ config, pkgs, lib, ... }:

{
  networking.hostName = "taylorpc";

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # NVIDIA driver
  myOptions.nvidia.mode = "disabled";

  imports = [
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/laptop.nix
  ];
}