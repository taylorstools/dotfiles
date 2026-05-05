{ config, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  services.asusd.enable = true;

  # Fix touchpad not working to wake from sleep
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="i2c", KERNEL=="i2c-ASCP1A00:00", ATTR{power/wakeup}="disabled"
  '';
}