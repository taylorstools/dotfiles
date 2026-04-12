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

    apps.${system} = {
      # Create bootstrap script app
      bootstrap = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "bootstrap";
          runtimeInputs = [ pkgs.nix pkgs.git pkgs.chezmoi pkgs.gum ];
          text = builtins.readFile ./bootstrap.sh;
        }}/bin/bootstrap";
      };

      # Script to switch to unstable branch within live ISO after install
      unstable-switch = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "unstable-switch";
          runtimeInputs = [ pkgs.nix pkgs.gum ];
          text = builtins.readFile ./unstable-switch.sh;
        }}/bin/unstable-switch";
      };

      # Script to fix mismatched LUKS UUIDs within live ISO after install
      # This still seems to be a bug: https://github.com/NixOS/nixpkgs/issues/62444
      bootfix = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "bootfix";
          runtimeInputs = [ pkgs.nix pkgs.gum ];
          text = builtins.readFile ./bootfix.sh;
        }}/bin/bootfix";
      };
    };
  };
}