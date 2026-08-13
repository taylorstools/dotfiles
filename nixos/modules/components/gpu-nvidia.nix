{ config, lib, ... }:

let
  cfg = config.myOptions.nvidia;
in
{
  options.myOptions.nvidia.mode = lib.mkOption {
    type = lib.types.enum [ "none" "proprietary" "open" "nouveau" "disabled" ];
    default = "none";
    description = "Which Nvidia driver setup to use.";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "proprietary") {
      services.xserver.videoDrivers = [ "nvidia" ];
      myOptions.graphics.enable = lib.mkDefault true;
      boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
      hardware.nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

    (lib.mkIf (cfg.mode == "open") {
      services.xserver.videoDrivers = [ "nvidia" ];
      myOptions.graphics.enable = lib.mkDefault true;
      boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
      hardware.nvidia = {
        modesetting.enable = true;
        open = true;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

    (lib.mkIf (cfg.mode == "nouveau") {
      services.xserver.videoDrivers = [ "nouveau" ];
      myOptions.graphics.enable = lib.mkDefault true;
    })

    (lib.mkIf (cfg.mode == "disabled") {
      boot.blacklistedKernelModules = [
        "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm"
      ];
      boot.kernelParams = [ "nouveau.modeset=0" ];
      services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
    })
  ];
}