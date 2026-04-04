{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-049ad563-d72d-4b6c-9fb3-c602e761ee06" = {
    device = "/dev/disk/by-uuid/049ad563-d72d-4b6c-9fb3-c602e761ee06";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
