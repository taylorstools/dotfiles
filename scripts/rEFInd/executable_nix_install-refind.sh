#!/usr/bin/env bash

set -euo pipefail

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "rEFInd Installer"

# Clone rEFI2nd

if [ ! -d "$HOME/rEFI2nd" ]; then
  gum log --level info "Cloning rEFI2nd..."
  git clone https://github.com/chenx-dust/rEFI2nd.git "$HOME/rEFI2nd"
else
  gum log --level warn "rEFI2nd already exists, skipping clone."
fi

# Build and install rEFInd

gum log --level info "Building and installing rEFInd..."
nix-shell "$HOME/scripts/rEFInd/shell.nix" --run "sudo refind-install"

# Copy config

gum log --level info "Copying rEFInd config..."
sudo cp -rf "$HOME/.dotfiles/refind/." /boot/EFI/refind/

gum log --level info "Done."