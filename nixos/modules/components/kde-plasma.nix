{ pkgs, ... }:

{
  # Enable KDE
  services.desktopManager.plasma6.enable = true;

  environment.sessionVariables.PATH = [
    "/run/wrappers/bin"
    "/home/taylor/.nix-profile/bin"
    "/etc/profiles/per-user/taylor/bin"
    "/nix/var/nix/profiles/default/bin"
    "/run/current-system/sw/bin"
  ];

  # Packages
  environment.systemPackages = with pkgs; [
    kdePackages.kdeconnect-kde
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qttools
    libsForQt5.qtstyleplugin-kvantum
    orchis-theme
    plasma-panel-colorizer
  ];
}