{ pkgs, ... }:

{
  imports = [
    ../../modules/components/asus-laptop.nix
    ../../modules/laptop.nix
    ./disko.nix
    ./hostid.nix
  ];

  networking.hostName = "taylorpc";

  environment.etc."vulkan/icd.d/radeon_icd.x86_64.json".source = 
  "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";

  myOptions = {
    nvidia.mode = "disabled";

    amd = {
      mode = "amdgpu";
      rocm.enable = true;
    };

    davinci.enable = true;

    llmChat.enable = true;

    roland.enable = true;
  };
}