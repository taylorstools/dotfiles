{ pkgs, ... }:

let
  username = "taylor";
in
{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  hardware.uinput.enable = true;
  
  users.users.${username}.extraGroups = [ "uinput" "input" ];

  environment.systemPackages = [
    pkgs.moonlight-qt
  ];
}