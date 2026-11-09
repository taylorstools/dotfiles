{ ... }:

let
  username = "taylor";
in
{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    # The tray icon is turned off at runtime with `system_tray = disabled` in
    # ~/.config/sunshine/sunshine.conf (dot_config/sunshine), not with
    # -DSUNSHINE_ENABLE_TRAY=OFF: a build flag changes the derivation, so
    # cache.nixos.org never has it and every nixpkgs bump recompiled
    # Sunshine from source on every host.
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