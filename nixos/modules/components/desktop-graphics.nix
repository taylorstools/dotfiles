{ config, lib, ... }:
let
  cfg = config.myOptions.graphics;
in
{
  options.myOptions.graphics = {
    enable = lib.mkEnableOption "hardware-accelerated desktop graphics";

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      example = false;
      description = ''
        32-bit driver support, needed for Steam, Wine, and older games.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      inherit (cfg) enable32Bit;
    };
  };
}