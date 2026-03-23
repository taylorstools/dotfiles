#!/usr/bin/env bash

set -euo pipefail

# Clone rEFInd repo
[ -d ~/rEFI2nd ] || git clone https://github.com/chenx-dust/rEFI2nd.git ~/rEFI2nd

# Build and install rEFInd
nix-shell ~/scripts/rEFInd/shell.nix --run "sudo refind-install"

# Copy config
sudo cp -r ~/.dotfiles/refind/. /boot/EFI/refind/