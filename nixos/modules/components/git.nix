{ config, pkgs, ... }:

let
  username = "taylor";
in
{
  programs.git = {
    enable = true;
    config.safe.directory = [ "/home/${username}/.dotfiles" ];
  }

  environment.systemPackages = with pkgs; [
    gh
  ];
}