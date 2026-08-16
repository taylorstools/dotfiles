{ pkgs, ... }:

{
  imports = [
    ./xone-idle-shutoff.nix
  ];

  hardware.xone.enable = true;

  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="045e", ATTR{idProduct}=="02e6", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="045e", ATTR{idProduct}=="02fe", TEST=="power/control", ATTR{power/control}="on"
  '';

  boot.extraModprobeConfig = ''
    options xone_dongle dyndbg=+p
  '';

  environment.systemPackages = with pkgs; [
    antimicrox
  ];
}