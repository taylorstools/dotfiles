{ config, pkgs, ... }:

{
  imports = [
    ./components/fix-plasma-env-vars.nix
    ./components/kde-plasma.nix
    ./components/sddm-autologin.nix
    ./components/xbox-controller.nix
  ];

  programs.steam.enable = true;

  environment.systemPackages = with pkgs; [
    jellyfin-media-player
  ];
}