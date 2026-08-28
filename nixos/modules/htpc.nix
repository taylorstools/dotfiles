{ pkgs, ... }:

{
  imports = [
    ./components/dim-overlay
    ./components/kde-plasma.nix
    ./components/sddm-autologin.nix
    ./components/ventoy-backup.nix
    ./components/xbox-controller.nix
  ];

  programs = {
    steam.enable = true;
    dim-overlay.enable = true;
    kdeconnect.enable = true;
  };

  environment.systemPackages = with pkgs; [
    easyeffects
    jellyfin-desktop
  ];
}