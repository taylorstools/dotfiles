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

    apps.${system} = {
      bootstrap = {
        type = "app";
        program = "${self}/bootstrap.sh";
        runtimeInputs = [ pkgs.git pkgs.nix ];
      };
    };
  };
}