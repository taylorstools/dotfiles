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
        default = 0.10;
        description = "Increment per darken/brighten step (0.0–1.0).";
      };
      min = lib.mkOption {
        type = lib.types.float;
        default = 0.01;
        description = "Minimum overlay opacity (closest to normal brightness).";
      };
      max = lib.mkOption {
        type = lib.types.float;
        default = 0.99;
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
        opacityStep    = cfg.opacity.step;
        opacityMin     = cfg.opacity.min;
        opacityMax     = cfg.opacity.max;
        opacityDefault = cfg.opacity.default;
      })
    ];
  };
}
