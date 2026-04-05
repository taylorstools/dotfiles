{ config, pkgs, ... }:

{
  imports = [
    ./components/dms.nix
    ./components/greetd.nix
    ./components/keyd.nix
    ./components/niri.nix
    ./components/thunar.nix
  ];
}