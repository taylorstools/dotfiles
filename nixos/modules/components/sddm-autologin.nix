{ config, pkgs, ... }:

let
  username = "taylor";
in
{
  #SDDM and Plasma auto-login
  services.displayManager = {
    sddm.enable = true;
    autoLogin = {
      enable = true;
      user = username;
    };
  };
}