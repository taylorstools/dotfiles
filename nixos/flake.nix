{
  description = "Taylor's NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, ... }:

  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit self inputs;
      };

      modules = [
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
      # Create bootstrap script app
      bootstrap = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "bootstrap";
          runtimeInputs = [ pkgs.chezmoi pkgs.git pkgs.gum pkgs.nix ];
          text = builtins.readFile ./bootstrap.sh;
        }}/bin/bootstrap";
      };

      # End-to-end install + post-install from the NixOS minimal ISO.
      # Run with:
      #   sudo nix run github:taylorstools/dotfiles?dir=nixos#bootstrap-minimal \
      #     --extra-experimental-features "nix-command flakes"
      bootstrap-minimal = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "bootstrap-minimal";
          runtimeInputs = [
            pkgs.gum
            pkgs.git
            pkgs.nix
            pkgs.curl
            pkgs.util-linux        # lsblk, mount, umount, mkswap, swapon/off, blkid
            pkgs.parted            # partprobe
            pkgs.gptfdisk          # cgdisk, sgdisk
            pkgs.cryptsetup        # LUKS
            pkgs.dosfstools        # mkfs.fat
            pkgs.e2fsprogs         # mkfs.ext4
            pkgs.nixos-install-tools  # nixos-install, nixos-generate-config, nixos-enter
          ];
          text = builtins.readFile ./bootstrap-minimal.sh;
        }}/bin/bootstrap-minimal";
      };

      # Script to switch to unstable branch within live ISO after install
      unstable-switch = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "unstable-switch";
          runtimeInputs = [ pkgs.gum pkgs.nix ];
          text = builtins.readFile ./unstable-switch.sh;
        }}/bin/unstable-switch";
      };

      # Script to fix mismatched LUKS UUIDs within live ISO after install
      # This still seems to be a bug: https://github.com/NixOS/nixpkgs/issues/62444
      bootfix = {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "bootfix";
          runtimeInputs = [ pkgs.gum pkgs.nix ];
          text = builtins.readFile ./bootfix.sh;
        }}/bin/bootfix";
      };
    };
  };
}