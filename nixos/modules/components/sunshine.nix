{ pkgs, lib, ... }:

let
  username = "taylor";
in
{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;

    package = pkgs.sunshine.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        (lib.cmakeBool "SUNSHINE_ENABLE_TRAY" false)
      ];
    });
  };

  hardware.uinput.enable = true;

  users.users.${username}.extraGroups = [ "uinput" "input" ];
}