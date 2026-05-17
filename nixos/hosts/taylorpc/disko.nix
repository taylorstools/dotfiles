{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-eui.ace42e00555d50ea2ee4ac0000000001";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";          # becomes /dev/mapper/cryptroot
              passwordFile = "/tmp/install/luks.key";
              extraFormatArgs = [
                "--type luks2"
                "--cipher aes-xts-plain64"
                "--key-size 512"
                "--pbkdf argon2id"
              ];
              settings = {
                allowDiscards = true;      # SSDs; drop for HDD
                # crypttabExtraOpts = [ "tpm2-device=auto" ];  # enable AFTER enrolling TPM
              };
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      rootFsOptions = {
        compression = "zstd";
        mountpoint  = "none";
        acltype     = "posixacl";
        xattr       = "sa";
        atime       = "off";
        "com.sun:auto-snapshot" = "false";
        # No encryption keys here — LUKS owns the crypto.
      };
      options.ashift = "12";

      datasets = {
        root = { type = "zfs_fs"; mountpoint = "/";     options.mountpoint = "legacy"; };
        nix  = { type = "zfs_fs"; mountpoint = "/nix";  options = { mountpoint = "legacy"; "com.sun:auto-snapshot" = "false"; }; };
        home = { type = "zfs_fs"; mountpoint = "/home"; options.mountpoint = "legacy"; };
      };
    };
  };
}