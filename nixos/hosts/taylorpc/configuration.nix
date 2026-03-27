{ config, pkgs, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ../../modules/niri.nix
  ];

  boot.extraModulePackages = [
    (pkgs.linuxPackages.callPackage ./hp-audio-fix.nix {})
  ];
}