{ config, pkgs, ... }:

{
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
    ];
  };

  services.tumbler.enable = true;

  environment.systemPackages = with pkgs; [
    file-roller
  ];
}