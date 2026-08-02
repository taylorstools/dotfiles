{ pkgs, inputs, ... }:

let
  orchis-theme = pkgs.callPackage ../../pkgs/orchis-theme {
    src = inputs.orchis-src;
  };
in
{
  services.desktopManager.plasma6.enable = true;

  environment.systemPackages = with pkgs; [
    kdePackages.kdeconnect-kde
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qttools
    libsForQt5.qtstyleplugin-kvantum
    plasma-panel-colorizer
  ] ++ [ orchis-theme ];
}