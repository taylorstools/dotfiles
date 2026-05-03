{ config, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-d7d9a112-93af-4c4c-a9be-9818d4481bd1" = {
    device = "/dev/disk/by-uuid/d7d9a112-93af-4c4c-a9be-9818d4481bd1";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
