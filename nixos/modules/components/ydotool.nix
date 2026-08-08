{ ... }:

let
  username = config.myOptions.user.name;
in
{
  programs.ydotool.enable = true;
  users.users.${username}.extraGroups = [ "ydotool" ];
}