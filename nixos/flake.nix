{
  description = "Taylor's NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/0403b4b7e8b2612657f0053a4c315e6c43eee9e6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sysboard-src = {
      url = "github:System64fumo/sysboard";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, ... }:

  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    sysboardOverlay = final: prev: {
      sysboard = final.callPackage ./modules/components/pkgs/sysboard.nix {
        src = inputs.sysboard-src;
      };
    };

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit self inputs;
      };

      modules = [
        { nixpkgs.overlays = [ sysboardOverlay ]; }
        inputs.disko.nixosModules.disko
        inputs.dms.nixosModules.dank-material-shell
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
      # # Create bootstrap script app
      # bootstrap = {
      #   type = "app";
      #   program = "${pkgs.writeShellApplication {
      #     name = "bootstrap";
      #     runtimeInputs = [ pkgs.chezmoi pkgs.git pkgs.gum pkgs.nix ];
      #     text = builtins.readFile ./bootstrap.sh;
      #   }}/bin/bootstrap";
      # };

      # # Script to switch to unstable branch within live ISO after install
      # unstable-switch = {
      #   type = "app";
      #   program = "${pkgs.writeShellApplication {
      #     name = "unstable-switch";
      #     runtimeInputs = [ pkgs.gum pkgs.nix ];
      #     text = builtins.readFile ./unstable-switch.sh;
      #   }}/bin/unstable-switch";
      # };

      # # Script to fix mismatched LUKS UUIDs within live ISO after install
      # # This still seems to be a bug: https://github.com/NixOS/nixpkgs/issues/62444
      # bootfix = {
      #   type = "app";
      #   program = "${pkgs.writeShellApplication {
      #     name = "bootfix";
      #     runtimeInputs = [ pkgs.gum pkgs.nix ];
      #     text = builtins.readFile ./bootfix.sh;
      #   }}/bin/bootfix";
      # };

      install = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "install";
          runtimeInputs = with pkgs; [
            coreutils cryptsetup curl gawk git gnused gptfdisk
            gum jq kmod mkpasswd nano parted util-linux zfs
          ];
          text = ''
            export DISKO_TEMPLATE="${./install/disko.nix}"
            export CONFIG_TEMPLATE="${./install/configuration.nix}"
            export FLAKE_TEMPLATE="${./install/flake.nix}"
            ${builtins.readFile ./install.sh}
          '';
        }}/bin/install";
      };

      postinstall = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "postinstall";
          runtimeInputs = with pkgs; [
            chezmoi git gum python3 unzip
          ];
          text = builtins.readFile ./postinstall.sh;
        }}/bin/postinstall";
      };
    };
  };
}