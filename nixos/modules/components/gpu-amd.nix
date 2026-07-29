{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.amd;
in
{
  options.myOptions.amd = {
    mode = lib.mkOption {
      type = lib.types.enum [ "none" "amdgpu" "radeon" ];
      default = "none";
      description = "AMD driver setup. amdgpu covers GCN 1+; radeon is pre-GCN only.";
    };

    rocm.enable = lib.mkEnableOption "ROCm/OpenCL compute (multi-GB closure)";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "amdgpu") {
      myOptions.graphics.enable = lib.mkDefault true;
      hardware.amdgpu.initrd.enable = true;
    })

    (lib.mkIf (cfg.mode == "radeon") {
      services.xserver.videoDrivers = [ "radeon" ];
      myOptions.graphics.enable = lib.mkDefault true;
    })

    (lib.mkIf cfg.rocm.enable {
      assertions = [{
        assertion = cfg.mode == "amdgpu";
        message = "myOptions.amd.rocm requires myOptions.amd.mode = \"amdgpu\"";
      }];

      hardware.amdgpu.opencl.enable = true;

      # Resolve, Blender HIP, PyTorch-ROCm hard-code this path
      systemd.tmpfiles.rules = [
        "L+ /opt/rocm - - - - ${pkgs.rocmPackages.clr}"
      ];
    })
  ];
}