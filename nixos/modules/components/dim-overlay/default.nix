{ config, lib, pkgs, ... }:

let
  cfg = config.programs.dim-overlay;
in
{
  options.programs.dim-overlay = {
    enable = lib.mkEnableOption "the dim-overlay screen dimmer";

    opacity = {
      step = lib.mkOption {
        type = lib.types.float;
        default = 0.05;
        description = "Default increment per darken/brighten step.";
      };
      fineStep = lib.mkOption {
        type = lib.types.float;
        default = 0.02;
        description = "Smaller step used when opacity is at or above fineStepThreshold.";
      };
      fineStepThreshold = lib.mkOption {
        type = lib.types.float;
        default = 0.90;
        description = "At or above this opacity, use fineStep instead of step.";
      };
      ultraStep = lib.mkOption {
        type = lib.types.float;
        default = 0.01;
        description = "Smallest step used when opacity is at or above ultraStepThreshold.";
      };
      ultraStepThreshold = lib.mkOption {
        type = lib.types.float;
        default = 0.96;
        description = "At or above this opacity, use ultraStep instead of fineStep.";
      };
      min = lib.mkOption {
        type = lib.types.float;
        default = 0.50;
        description = "Minimum overlay opacity (closest to normal brightness).";
      };
      max = lib.mkOption {
        type = lib.types.float;
        default = 1.00;
        description = "Maximum overlay opacity (closest to fully black).";
      };
      default = lib.mkOption {
        type = lib.types.float;
        default = 0.50;
        description = "Initial opacity when overlay starts.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.callPackage ./package.nix {
        opacityStep               = cfg.opacity.step;
        opacityFineStep           = cfg.opacity.fineStep;
        opacityFineStepThreshold  = cfg.opacity.fineStepThreshold;
        opacityUltraStep          = cfg.opacity.ultraStep;
        opacityUltraStepThreshold = cfg.opacity.ultraStepThreshold;
        opacityMin                = cfg.opacity.min;
        opacityMax                = cfg.opacity.max;
        opacityDefault            = cfg.opacity.default;
      })
    ];
  };
}
