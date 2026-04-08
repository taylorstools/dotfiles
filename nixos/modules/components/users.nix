{ config, pkgs, ... }:

let
  username = "taylor";
  avatar = ./assets/taylor.png;
in
{
  users.users.${username} = {
    isNormalUser = true;
    description = "Taylor";
    extraGroups = [ "networkmanager" "wheel" "input" ];
  };

  # Passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Profile picture
  systemd.tmpfiles.rules = [
    "d /var/lib/AccountsService/icons 0755 root root -"
    "L+ /var/lib/AccountsService/icons/${username} - - - - ${avatar}"
    "f+ /var/lib/AccountsService/users/${username} 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/${username}\\n"
  ];
}