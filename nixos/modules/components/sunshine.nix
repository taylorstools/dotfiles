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

  # nixpkgs' sunshine module still sets the legacy services.avahi.publish.*
  # options (at mkDefault), which the avahi module now warns are obsolete on
  # every eval. Null them out and set the equivalent settings directly.
  services.avahi = {
    publish.enable = null;
    publish.userServices = null;
    settings.publish = {
      disable-publishing = false;
      disable-user-service-publishing = false;
      publish-addresses = true;
    };
  };

  hardware.uinput.enable = true;

  users.users.${username}.extraGroups = [ "uinput" "input" ];
}