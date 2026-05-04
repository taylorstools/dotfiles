{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-5bb247ef-7ce2-4da9-9e73-231f9c132b8c" = {
    device = "/dev/disk/by-uuid/5bb247ef-7ce2-4da9-9e73-231f9c132b8c";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
