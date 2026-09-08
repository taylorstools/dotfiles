{ pkgs, ... }:

{
  imports = [
    ./xpadneo-idle-shutoff.nix
  ];

  #hardware.xone.enable = true;
  hardware.xpadneo.enable = true;

  # For AntiMicroX to work in Wayland
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
  '';

  environment.systemPackages = with pkgs; [
    antimicrox
  ];
}