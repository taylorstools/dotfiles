{ ... }:

{
  networking.hostName = "taylorpc";

  # NVIDIA driver
  myOptions.nvidia.mode = "disabled";

  imports = [
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
    ../../modules/laptop.nix
  ];
}