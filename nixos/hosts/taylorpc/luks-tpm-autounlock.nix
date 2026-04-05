{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-58db4817-c1ce-49cd-841d-98255ac1dbac" = {
    device = "/dev/disk/by-uuid/58db4817-c1ce-49cd-841d-98255ac1dbac";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
