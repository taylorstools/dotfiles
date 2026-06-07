{ ... }:

{
  systemd.user = {
    extraConfig = ''
      DefaultTimeoutStopSec=10s
    '';

    services.plasma-plasmashell = {
      overrideStrategy = "asDropin";
      serviceConfig.TimeoutStopSec = "10s";
    };
  };

  systemd.services."user@" = {
    overrideStrategy = "asDropin";
    serviceConfig.TimeoutStopSec = "10s";
  };

  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";
}