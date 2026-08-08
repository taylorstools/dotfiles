{ config, lib, ... }:

let
  cfg = config.myOptions.user;
in
{
  options.myOptions.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "taylor";
      description = "Login name of the primary user account.";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "Taylor";
      description = "Display name for the primary user account.";
    };

    avatar = lib.mkOption {
      type = lib.types.path;
      default = ./assets/taylor.png;
      description = "Profile picture for the primary user account.";
    };
  };

  config = {
    users.users.${cfg.name} = {
      isNormalUser = true;
      inherit (cfg) description;
      extraGroups = [ "networkmanager" "wheel" "input" ];
      hashedPasswordFile = "/etc/users/${cfg.name}.hash";
    };

    security.sudo.wheelNeedsPassword = false;
    users.users.root.hashedPassword = "!";

    systemd.tmpfiles.rules = [
      "d /var/lib/AccountsService/icons 0755 root root -"
      "L+ /var/lib/AccountsService/icons/${cfg.name} - - - - ${cfg.avatar}"
      "f+ /var/lib/AccountsService/users/${cfg.name} 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/${cfg.name}\\n"
    ];
  };
}