{ ... }:

{
  systemd.extraConfig = ''
    DefaultTimeoutStopSec=10s
  '';

  systemd.user.extraConfig = ''
    DefaultTimeoutStopSec=10s
  '';
}