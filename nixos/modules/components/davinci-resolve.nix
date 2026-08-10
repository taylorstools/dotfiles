{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.davinci;

  # Resolve needs a GPU compute backend: CUDA on Nvidia, OpenCL/ROCm on AMD.
  # Intel iGPUs are not a supported target on Linux.
  hasCuda = builtins.elem config.myOptions.nvidia.mode [ "proprietary" "open" ];
  hasRocm = config.myOptions.amd.rocm.enable;
in
{
  options.myOptions.davinci.enable =
    lib.mkEnableOption "DaVinci Resolve (requires a CUDA- or ROCm-capable GPU)";

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = hasCuda || hasRocm;
      message = ''
        myOptions.davinci.enable requires a GPU compute backend. Set either
        myOptions.amd.rocm.enable = true, or myOptions.nvidia.mode to
        "proprietary" or "open".
      '';
    }];

    environment.systemPackages = [
      inputs.davinci-resolve.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}