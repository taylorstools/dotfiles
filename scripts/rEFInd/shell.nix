# shell.nix
{ pkgs ? import <nixpkgs> {} }:

let
  # Use the absolute path
  refindSrc = pkgs.lib.cleanSource /home/taylor/rEFInd;
in

pkgs.mkShell {
  buildInputs = [
    (pkgs.refind.overrideAttrs (old: {
      src = refindSrc;
    }))
    pkgs.efibootmgr
  ];
}
