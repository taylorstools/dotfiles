{ config, pkgs, ... }:

{
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            leftmeta = "overload(meta, macro(leftmeta+d))";
          };
        };

        extraConfig = ''
          overload_tap_timeout = 150
        '';
      };
    };
  };
}