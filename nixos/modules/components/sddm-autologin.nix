{ config, ... }:

let
  username = config.myOptions.user.name;
in
{
  services.displayManager = {
    sddm.enable = true;
    autoLogin = {
      enable = true;
      user = username;
    };
  };
}