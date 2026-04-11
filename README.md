# Dotfiles
Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation script
Install a minimal NixOS system, boot into it, connect to Wi-Fi with `nmtui` if needed, then run this command to configure the system:
```sh
nix run github:taylorstools/dotfiles?dir=nixos#bootstrap --extra-experimental-features "nix-command flakes"
```
This bootstrap script will handle downloading this repo, updating the flake, rebuilding the system configuration, applying the dotfiles with chezmoi, and optionally setting up rEFInd bootloader and TPM autounlock for LUKS.

## Error mounting root filesystem
If you selected to encrypt the system and encounter "An error occurred in stage 1 of the boot process, which must mount the root filesystem..." when booting into the new NixOS install, boot back into the NixOS live ISO and run the following command to switch your system to the unstable channel and rebuild. Chances are good it will fix it.
```sh
nix run github:taylorstools/dotfiles?dir=nixos#unstable-switch --extra-experimental-features "nix-command flakes"
```