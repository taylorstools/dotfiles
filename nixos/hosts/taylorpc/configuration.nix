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

    roland.enable = true;
  };
}