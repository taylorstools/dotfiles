{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  # TPM2 auto-unlock is intentionally off on taylorpc: the LUKS passphrase is
  # typed at the Plymouth prompt on every boot instead
  # (myOptions.plymouth.enable in ./configuration.nix).
  #
  # To go back to auto-unlock, uncomment the line below and re-enroll the
  # keyslot:
  #   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 \
  #     /dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b473ad3ac-part3
  #
  # boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];
}
