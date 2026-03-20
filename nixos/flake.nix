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
      # future hosts go here:
      # laptop = mkHost "laptop";
      # server = mkHost "server";
    };

    apps.${system} = {
      bootstrap = {
        type = "app";
        program = "${self}/bootstrap.sh";
        # optionally you can add runtimeInputs if your script depends on packages
        # runtimeInputs = [ pkgs.git pkgs.nix ];
      };
    };
  };
}