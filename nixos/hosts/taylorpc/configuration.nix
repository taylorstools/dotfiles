{ pkgs, ... }:

{
  imports = [
    ../../modules/components/asus-laptop.nix
    ../../modules/laptop.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "taylorpc";

  myOptions = {
    nvidia.mode = "disabled";

    amd = {
      mode = "amdgpu";
      rocm.enable = true;
    };

    davinci.enable = true;

    howdy = {
      enable = true;
      # Stable by-path node for the IR sensor; /dev/videoN can move on reboot.
      devicePath = "/dev/video2";
    };

    roland.enable = true;
  };
}