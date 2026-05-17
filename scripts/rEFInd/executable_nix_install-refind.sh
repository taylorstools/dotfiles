#!/usr/bin/env bash

set -euo pipefail

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "rEFInd Installer"

REFIND_EFI="/boot/EFI/refind/refind_x64.efi"

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

# Sign rEFInd with sbctl so Secure Boot will accept it
if ! sudo test -f "$REFIND_EFI"; then
  gum log --level warn "rEFInd binary not found at $REFIND_EFI, skipping signing."
elif ! sudo test -d /var/lib/sbctl/keys; then
  gum log --level warn "sbctl keys not found, skipping signing."
  gum log --level info "Run prepare-secure-boot.sh first to create keys, then re-run this script."
else
  gum log --level info "Signing rEFInd with sbctl..."
  nix-shell -p sbctl --run "sudo sbctl sign -s '$REFIND_EFI'"
fi

gum log --level info "Done."