{ config, pkgs, ... }:

{
  imports = [
    ./components/kde-plasma.nix
    ./components/sddm-autologin.nix
    ./components/xbox-controller.nix
  ];

  environment.systemPackages = with pkgs; [
    jellyfin-media-player
  ];
}