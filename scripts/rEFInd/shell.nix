{ pkgs ? import <nixpkgs> {} }:

let
  oldNixpkgs = import (pkgs.fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs";
    rev    = "8e1e15cf11e50d5a5466caf4479b0981a698e305";
    sha256 = "1l9x7jjhkk84yxmnbg6iqd11ws5y7b2cxi2by6zhfd8c3ip5x40k";
  }) {};

  refindSrc = pkgs.lib.cleanSource /home/taylor/rEFI2nd;

  rEFI2nd = (pkgs.refind.override { gnu-efi = oldNixpkgs.gnu-efi; }).overrideAttrs (old: {
    src = refindSrc;
    patches = [];
  });
in
pkgs.mkShell {
  buildInputs = [
    rEFI2nd
    pkgs.efibootmgr
  ];
}