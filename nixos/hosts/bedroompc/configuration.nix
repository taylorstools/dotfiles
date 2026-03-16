{ config, pkgs, ... }:

{
  imports =
    [
      #./hardware-configuration.nix
    ];

  # Hostname
  networking.hostName = "bedroompc";

  hardware.xone.enable = true;

  # Packages
  environment.systemPackages = with pkgs; [
    antimicrox
    kdePackages.kdeconnect-kde
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    orchis-theme
    plasma-panel-colorizer
  ];

  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
  '';

  #SDDM and Plasma auto-login
  services.displayManager = {
    sddm.enable = true;
    autoLogin = {
      enable = true;
      user = "taylor";
    };
  };

  #Enable KDE
  services.desktopManager.plasma6.enable = true;

  system.stateVersion = "25.11"; # Did you read the comment?
}
