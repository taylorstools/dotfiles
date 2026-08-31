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
    plymouth = {
      enable = true;
      theme = "minimal";
      themePackages = [
        (pkgs.callPackage ../../pkgs/plymouth-theme-minimal/package.nix { })
      ];
    };

    roland.enable = true;
  };
}