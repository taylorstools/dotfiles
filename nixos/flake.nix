{
  description = "Taylor's NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit self;
      };

      modules = [
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
        runtimeInputs = [ pkgs.git pkgs.nix ];
        text = builtins.readFile ./bootstrap.sh;
      }}/bin/bootstrap";
    };
  };
}