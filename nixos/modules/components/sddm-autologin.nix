{ ... }:

let
  username = config.myOptions.user.name;
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