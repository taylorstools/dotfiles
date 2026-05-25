{ config, pkgs, ... }:

{
  hardware.cpu.amd.ryzen-smu.enable = true;

  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  services.asusd.enable = true;

  services.supergfxd = {
    enable = true;
    settings = {
      mode = "Integrated";
      vfio_enable = false;
      vfio_save = false;
      always_reboot = false;
      no_logind = false;
      logout_timeout_s = 180;
      hotplug_type = "None";
    };
  };
}