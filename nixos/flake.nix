{
  description = "Taylor's NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:

  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit self;
      };

      modules = [
        ./modules/default.nix
        ./hosts/${hostName}/configuration.nix
        ./hosts/${hostName}/hardware-configuration.nix
      ];
    };

    # Automatically create hosts based on dirs in "hosts" folder
    hosts = builtins.attrNames (
      nixpkgs.lib.filterAttrs
        (_name: type: type == "directory")
        (builtins.readDir ./hosts)
    );
  in {
    nixosConfigurations = builtins.listToAttrs (
      map (hostName: {
        name = hostName;
        value = mkHost hostName;
      }) hosts
    );

    # Create bootstrap script app
    apps.${system}.bootstrap = {
      type = "app";
      program = "${pkgs.writeShellApplication {
        name = "bootstrap";
        runtimeInputs = [ pkgs.nix pkgs.git pkgs.chezmoi pkgs.gum ];
        text = builtins.readFile ./bootstrap.sh;
      }}/bin/bootstrap";
    };

    # Create bootstrap script app (run in live ISO)
    apps.${system}.bootstrap-liveiso = {
      type = "app";
      program = "${pkgs.writeShellApplication {
        name = "bootstrap-liveiso";
        runtimeInputs = [ pkgs.nix pkgs.git pkgs.chezmoi pkgs.gum ];
        text = builtins.readFile ./bootstrap-liveiso.sh;
      }}/bin/bootstrap-liveiso";
    };
  };
}