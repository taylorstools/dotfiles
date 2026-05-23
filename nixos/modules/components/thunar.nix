{ config, pkgs, ... }:

{
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
    ];
  };

  services.tumbler.enable = true;

  systemd.tmpfiles.rules = let
    gtkDark = pkgs.writeText "gtk-dark-settings.ini" ''
      [Settings]
      gtk-application-prefer-dark-theme=1
    '';
  in [
    "L+ /root/.config/gtk-3.0/settings.ini - - - - ${gtkDark}"
    "L+ /root/.config/gtk-4.0/settings.ini - - - - ${gtkDark}"
  ];

  environment.systemPackages = with pkgs; [
    file-roller
  ];
}