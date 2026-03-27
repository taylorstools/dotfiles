{ config, pkgs, ... }:

{
  networking.hostName = "taylorpc";

  imports = [
    ../../modules/niri.nix
  ];

  boot.kernelParams = [
    "snd_hda_intel.dmic_detect=0"
  ];

  boot.extraModprobeConfig = ''
    options snd-hda-intel model=alc287-hp
  '';
}