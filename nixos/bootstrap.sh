#!/usr/bin/env bash

set -euo pipefail
clear

if [ "$(id -u)" -eq 0 ]; then
  gum log --level error "Script should not be ran with sudo or as root."
  exit 1
fi

REPO="https://github.com/taylorstools/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS Bootstrap Script"

# ===== Clone or update dotfiles =====

gum log --level info "Cloning dotfiles..."
if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$REPO" "$DOTFILES_DIR"
else
  gum log --level warn "Dotfiles already exist, pulling latest..."
  git -C "$DOTFILES_DIR" pull
fi

# ===== Select host =====

hosts=()
for dir in "$DOTFILES_DIR/nixos/hosts"/*/; do
  [ -d "$dir" ] || continue
  hosts+=("$(basename "$dir")")
done

echo ""
gum log --level info "Select host configuration:"
HOST=$(printf "%s\n" "${hosts[@]}" | gum choose --header "Choose the host for this configuration:")

[ -z "$HOST" ] && { gum log --level error "No host selected."; exit 1; }

# ===== rEFInd (taylorpc only) =====

REFIND_ANSWER="n"
if [[ "$HOST" == "taylorpc" ]]; then
  echo
  gum confirm "Configure rEFInd?" && REFIND_ANSWER="y" || REFIND_ANSWER="n"
fi

# ===== Copy hardware configuration =====

if [ -f "/etc/nixos/hardware-configuration.nix" ]; then
  gum log --level info "Copying hardware-configuration.nix..."
  sudo cp -f \
    "/etc/nixos/hardware-configuration.nix" \
    "$HOME/.dotfiles/nixos/hosts/$HOST/hardware-configuration.nix"
fi

# ===== Update flake =====

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "Flake Update & Rebuild"

gum log --level info "Updating Nix flake..."
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_DIR/nixos"

# ===== Apply system configuration =====

echo ""
gum log --level info "Applying system configuration..."
set +e
sudo nixos-rebuild switch --flake "$DOTFILES_DIR/nixos#$HOST"
rc=$?
set -e

case $rc in
  0)
    ;;
  4)
    gum log --level warn "Rebuild succeeded but some user services could not reload (expected during bootstrap from TTY)."
    ;;
  *)
    gum log --level error "nixos-rebuild failed with exit status $rc"
    exit $rc
    ;;
esac

# ===== Apply dotfiles =====

gum log --level info "Applying dotfiles with chezmoi..."
chezmoi init --source "$DOTFILES_DIR" --apply $REPO --force

# ===== LUKS TPM autounlock =====

"$HOME/scripts/luks-tpm-autounlock.sh" --hostname "$HOST"

# ===== Set user directories =====

"$HOME/scripts/update-user-dirs.sh"

# ===== rEFInd =====

if [[ "$REFIND_ANSWER" == "y" ]]; then
  "$HOME/scripts/rEFInd/nix_install-refind.sh"
fi

# ===== Done =====

echo ""
gum log --level info "BOOTSTRAP SCRIPT COMPLETE."

if gum confirm "Reboot now?"; then
  [ -d "$HOME/rEFI2nd" ] && rm -rf "$HOME/rEFI2nd"
  [ -d "/etc/nixos" ] && sudo mv /etc/nixos /etc/nixos.old
  sudo reboot
fi