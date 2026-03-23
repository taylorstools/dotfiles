{ pkgs ? import <nixpkgs> {} }:

let
  refindSrc = pkgs.lib.cleanSource /home/taylor/rEFI2nd;
in

pkgs.mkShell {
  buildInputs = [
    (pkgs.refind.overrideAttrs (old: {
      src = refindSrc;
      patches = [];
    }))
    pkgs.efibootmgr
  ];
}
