{ config, ... }:

let
  username = "taylor";
in
{
  programs.ydotool.enable = true;
  users.users.${username}.extraGroups = [ "ydotool" ];
}