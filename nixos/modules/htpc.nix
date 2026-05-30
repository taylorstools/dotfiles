{ pkgs, ... }:

{
  imports = [
    ./components/dim-overlay
    #./components/fix-plasma-env-vars.nix
    ./components/kde-plasma.nix
    ./components/sddm-autologin.nix
    ./components/xbox-controller.nix
  ];

  programs = {
    steam.enable = true;
    dim-overlay.enable = true;
  };

  environment.systemPackages = with pkgs; [
    jellyfin-media-player
  ];
}