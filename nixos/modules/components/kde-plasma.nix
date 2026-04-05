{ config, pkgs, ... }:

{
  # Enable KDE
  services.desktopManager.plasma6.enable = true;

  # Packages
  environment.systemPackages = with pkgs; [
    kdePackages.kdeconnect-kde
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    orchis-theme
    plasma-panel-colorizer
  ];
}