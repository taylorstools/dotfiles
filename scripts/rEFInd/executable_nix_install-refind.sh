#!/usr/bin/env bash

set -euo pipefail

# Clone rEFInd repo
[ -d $HOME/rEFI2nd ] || git clone https://github.com/chenx-dust/rEFI2nd.git $HOME/rEFI2nd

# Build and install rEFInd
nix-shell $HOME/scripts/rEFInd/shell.nix --run "sudo refind-install"

# Copy config
sudo cp -rf $HOME/.dotfiles/refind/. /boot/EFI/refind/