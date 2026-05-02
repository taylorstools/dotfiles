{ config, lib, ... }:

let
  cfg = config.myHardware.nvidia;
in
{
  options.myHardware.nvidia.mode = lib.mkOption {
    type = lib.types.enum [ "proprietary" "open" "nouveau" "disabled" ];
    default = "disabled";
    description = "Which Nvidia driver setup to use.";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "proprietary") {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.graphics.enable = true;
      hardware.nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

    (lib.mkIf (cfg.mode == "open") {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.graphics.enable = true;
      hardware.nvidia = {
        modesetting.enable = true;
        open = true;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

    (lib.mkIf (cfg.mode == "nouveau") {
      services.xserver.videoDrivers = [ "nouveau" ];
      hardware.graphics.enable = true;
    })

    (lib.mkIf (cfg.mode == "disabled") {
      boot.blacklistedKernelModules = [
        "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm"
      ];
      boot.kernelParams = [ "nouveau.modeset=0" ];
      services.xserver.videoDrivers =
        lib.mkForce (lib.filter (d: d != "nvidia" && d != "nouveau")
          (config.services.xserver.videoDrivers or [ "modesetting" ]));
    })
  ];
}