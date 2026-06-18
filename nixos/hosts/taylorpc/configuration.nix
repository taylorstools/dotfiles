{ ... }:

{
  networking.hostName = "taylorpc";

  # NVIDIA driver
  myOptions.nvidia.mode = "disabled";

  imports = [
    ../../modules/laptop.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];
}