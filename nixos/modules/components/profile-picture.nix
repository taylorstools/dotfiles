{ config, pkgs, ... }:

let
  username = "taylor";
  avatar = ./components/assets/taylor.png;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/AccountsService/icons 0755 root root -"
    "L+ /var/lib/AccountsService/icons/${username} - - - - ${avatar}"
    "f+ /var/lib/AccountsService/users/${username} 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/${username}\\n"
  ];
}