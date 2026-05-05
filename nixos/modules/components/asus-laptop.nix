{ config, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  services.asusd.enable = true;

  # Fix touchpad not working to wake from sleep
  systemd.services.touchpad-wakeup = {
    description = "Disable touchpad wakeup";
    wantedBy = [ "multi-user.target" "post-resume.target" ];
    after = [ "post-resume.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo disabled > /sys/bus/i2c/devices/i2c-ASCP1A00:00/power/wakeup'";
    };
  };
}