{ config, pkgs, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ../../modules/luks-tpm-autounlock.nix
    ../../modules/niri.nix
  ];
}