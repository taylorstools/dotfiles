#!/usr/bin/env bash

set -euo pipefail

# Clone rEFInd repo
[ -d ~/rEFInd ] || git clone https://github.com/RefindPlusRepo/rEFInd.git ~/rEFInd

# Apply MR #55
patch_file=~/scripts/rEFInd/refind-duplicate-tools.patch

git -C ~/rEFInd apply "$patch_file" || true

# Build and install rEFInd
nix-shell ~/scripts/rEFInd/shell.nix --run "sudo refind-install"

sudo cp -r ~/scripts/rEFInd/refind/. /boot/EFI/refind/