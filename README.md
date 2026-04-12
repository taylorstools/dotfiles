# Dotfiles

Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation script

Install a minimal NixOS system, boot into it, connect to Wi-Fi with `nmtui` if needed, then run this command to configure the system:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#bootstrap --extra-experimental-features "nix-command flakes"
```

This bootstrap script will handle downloading this repo, updating the flake, rebuilding the system configuration, applying the dotfiles with chezmoi, and optionally setting up rEFInd bootloader and TPM autounlock for LUKS.

## Error mounting root filesystem

If you selected to encrypt the system and encounter "An error occurred in stage 1 of the boot process, which must mount the root filesystem..." when booting into the new NixOS install, boot back into the NixOS live ISO and run the following command:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#bootfix --extra-experimental-features "nix-command flakes"
```

A script will run which will check your installed system's `hardware-configuration.nix` for a UUID mismatch in this part of the config:

```nix
boot.initrd.luks.devices."luks-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX".device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
```

These UUIDs are supposed to match, but there is a [long-running bug](https://github.com/NixOS/nixpkgs/issues/62444) where a totally different UUID follows `/dev/disk/by-uuid/` instead. The script corrects this part of the config and rebuilds your system so you can boot into it.