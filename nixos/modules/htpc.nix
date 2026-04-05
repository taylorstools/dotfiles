{ config, pkgs, ... }:

{
  imports = [
    ./components/kde-plasma.nix
    ./components/xbox-controller.nix
  ];
}