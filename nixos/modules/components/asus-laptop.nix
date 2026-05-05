{ config, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  services.asusd.enable = true;
}