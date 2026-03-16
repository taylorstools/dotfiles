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
  in {
    nixosConfigurations = {
      bedroompc = mkHost "bedroompc";
      # future hosts go here:
      # laptop = mkHost "laptop";
      # server = mkHost "server";
    };
  };
}
