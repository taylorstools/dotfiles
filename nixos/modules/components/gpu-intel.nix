{ config, lib, pkgs, ... }:
let cfg = config.myOptions.intel;
in {
  options.myOptions.intel.mode = lib.mkOption {
    type = lib.types.enum [ "none" "modern" "legacy" ];
    default = "none";
    description = "Intel iGPU. modern = Broadwell (2014)+; legacy = older.";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "modern") {
      myOptions.graphics.enable = lib.mkDefault true;
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
      ];
      hardware.graphics.extraPackages32 = [
        pkgs.driversi686Linux.intel-media-driver
      ];
      environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
    })

    (lib.mkIf (cfg.mode == "legacy") {
      myOptions.graphics.enable = lib.mkDefault true;
      hardware.graphics.extraPackages = [ pkgs.intel-vaapi-driver ];
      environment.sessionVariables.LIBVA_DRIVER_NAME = "i965";
    })
  ];
}