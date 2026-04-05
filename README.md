# Dotfiles
Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation script
Install a minimal NixOS system, boot into it, then run this command to configure the system:
```sh
nix run github:taylorstools/dotfiles?dir=nixos#bootstrap --extra-experimental-features "nix-command flakes"
```
This bootstrap script will handle downloading this repo, updating the flake, rebuilding the system configuration, applying the dotfiles with chezmoi, and optionally setting up rEFInd bootloader and TPM autounlock for LUKS.