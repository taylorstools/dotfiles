{ config, pkgs, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ../../modules/niri.nix
  ];
}