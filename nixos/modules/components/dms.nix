{ config, pkgs, ... }:

{    
  programs.dms-shell = {
    enable = true;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };
    
    enableDynamicTheming = true;
    enableClipboardPaste = true;
  };

  environment.systemPackages = with pkgs; [
    accountsservice
    adw-gtk3
    hypridle
    swaybg
  ];
}