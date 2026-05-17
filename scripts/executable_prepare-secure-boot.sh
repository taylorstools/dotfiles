#!/usr/bin/env bash
set -euo pipefail

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "Prepare Secure Boot"

REFIND_EFI="/boot/EFI/refind/refind_x64.efi"

nix-shell -p sbctl gum --run "
    set -euo pipefail

    if sudo test -d /var/lib/sbctl/keys; then
        gum log -l info 'Secure Boot keys already exist; skipping create-keys'
    else
        gum log -l info 'Creating Secure Boot keys'
        sudo sbctl create-keys
    fi

    if sudo test -f '$REFIND_EFI'; then
        gum log -l info 'Signing and registering rEFInd' path '$REFIND_EFI'
        sudo sbctl sign -s '$REFIND_EFI'
    else
        gum log -l warn 'rEFInd binary not found, skipping sign step' path '$REFIND_EFI'
        gum log -l info 'Sign it later with: sudo sbctl sign -s <path-to-refind_x64.efi>'
    fi

    gum log -l info 'Current sbctl status'
    sudo sbctl status
"