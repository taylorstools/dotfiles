{
  description = "Taylor's NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lanzaboote = (import ./lon.nix).inputs.lanzaboote;
  };

  outputs = { self, nixpkgs, lanzaboote, ... }:
  let
    system = "x86_64-linux";

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit self;
      };

      modules = [
        lanzaboote.nixosModules.lanzaboote
        ./hosts/default.nix
        ./hosts/${hostName}/configuration.nix
        ./hosts/${hostName}/hardware-configuration.nix
      ];
    };

    pkgs = import nixpkgs { inherit system; };
  in {
    nixosConfigurations = {
      bedroompc = mkHost "bedroompc";
      taylorpc = mkHost "taylorpc";
    };

    apps.${system}.bootstrap = {
      type = "app";
      program = "${pkgs.writeShellApplication {
        name = "bootstrap";
        runtimeInputs = [ pkgs.git pkgs.nix pkgs.chezmoi pkgs.gum ];
        text = builtins.readFile ./bootstrap.sh;
      }}/bin/bootstrap";
    };
  };
}