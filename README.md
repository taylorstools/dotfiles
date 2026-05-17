# Dotfiles

Dotfiles for my NixOS systems, managed by [chezmoi](https://github.com/twpayne/chezmoi).

## Installation Script

Boot into a minimal NixOS ISO, connect to Wi-Fi with `nmtui` if needed, then run this command to install the base system:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#install --extra-experimental-features "nix-command flakes"
```

## Post-Install Script

After it installs the system, boot into it, then login with the temporary password. Connect to Wi-Fi again with `nmtui` if needed, then run the post-install script:

```sh
nix run github:taylorstools/dotfiles?dir=nixos#postinstall
```