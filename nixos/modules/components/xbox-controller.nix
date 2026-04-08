{ config, pkgs, ... }:

{
  hardware.xone.enable = true;

  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
  '';

  environment.systemPackages = with pkgs; [
    antimicrox
  ];
}