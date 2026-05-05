{ config, ... }:

let
  username = "taylor";
  description = "Taylor";
  avatar = ./assets/taylor.png;
in
{
  users.users.${username} = {
    isNormalUser = true;
    description = description;
    extraGroups = [ "networkmanager" "wheel" "input" ];
  };

  # Passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Disable root
  users.users.root.hashedPassword = "!";

  # Profile picture
  systemd.tmpfiles.rules = [
    "d /var/lib/AccountsService/icons 0755 root root -"
    "L+ /var/lib/AccountsService/icons/${username} - - - - ${avatar}"
    "f+ /var/lib/AccountsService/users/${username} 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/${username}\\n"
  ];
}