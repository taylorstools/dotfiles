{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-4431368b-431b-4edf-9690-a8a7abb59452" = {
    device = "/dev/disk/by-uuid/4431368b-431b-4edf-9690-a8a7abb59452";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
