{ config, pkgs, ... }:

{
  hardware.xone.enable = true;

  # Packages
  environment.systemPackages = with pkgs; [
    antimicrox
  ];

  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
  '';
}