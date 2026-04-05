{ config, pkgs, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ./luks-tpm-autounlock.nix
    ../../modules/niri.nix
  ];
}