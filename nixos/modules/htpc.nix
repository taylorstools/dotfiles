{ config, pkgs, ... }:

{
  imports = [
    ./components/kde-plasma.nix
    ./components/sddm-autologin.nix
    ./components/xbox-controller.nix
  ];
}