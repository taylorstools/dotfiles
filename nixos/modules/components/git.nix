{ config, pkgs, ... }:

let
  username = config.myOptions.user.name;
in
{
  programs.git = {
    enable = true;
    config.safe.directory = [ "/home/${username}/.dotfiles" ];
  };

  environment.systemPackages = with pkgs; [
    gh
  ];
}