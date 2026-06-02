{ ... }:

{
  imports = [
    ./amd-undervolt.nix
  ];

  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  services.asusd.enable = true;

  systemd.services.asus-shutdown.restartIfChanged = false;

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