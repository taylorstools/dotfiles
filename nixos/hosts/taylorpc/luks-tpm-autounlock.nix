{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-bfd9ccd9-e9cc-4678-b51a-58801e2c681d" = {
    device = "/dev/disk/by-uuid/bfd9ccd9-e9cc-4678-b51a-58801e2c681d";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
