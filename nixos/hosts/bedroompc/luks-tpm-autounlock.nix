{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-9acffc25-f2f4-4c4f-86db-f73765a795b3" = {
    device = "/dev/disk/by-uuid/9acffc25-f2f4-4c4f-86db-f73765a795b3";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}