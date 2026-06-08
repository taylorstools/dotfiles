{ ... }:

{
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";

  systemd.user.extraConfig = ''
    DefaultTimeoutStopSec=10s
  '';
}