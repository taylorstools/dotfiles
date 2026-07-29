{ ... }:

{
  networking.hostName = "taylorpc";

  myOptions.nvidia.mode = "disabled";

  myOptions.amd = {
    mode = "amdgpu";
    rocm.enable = true;
  };

  imports = [
    ../../modules/laptop.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];
}