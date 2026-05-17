#!/usr/bin/env bash
set -euo pipefail
clear

if [ "$(id -u)" -eq 0 ]; then
  gum log --level error "Don't run as root, sudo is invoked as needed."
  exit 1
fi

REPO="https://github.com/taylorstools/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"
INSTALLER_DIR="/etc/nixos-installer"
ETC_NIXOS="/etc/nixos"
HOST=$(hostname)
HOST_DIR="$DOTFILES_DIR/nixos/hosts/$HOST"

# Per-host source-of-truth files. /etc/nixos owns them; dotfiles holds a copy
# that's refreshed from /etc/nixos before each rebuild.
SYNC_FILES=(
  hardware-configuration.nix
  hostid.nix
  disko.nix
)

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS Post-Install Script"

gum log --level info "Detected host: $HOST"

if [ ! -d "$INSTALLER_DIR" ]; then
  gum log --level warn "No $INSTALLER_DIR, was this booted from install.sh?"
  gum confirm "Continue anyway?" || exit 1
fi

# Prompt to change default password
if [ -f "$INSTALLER_DIR/configuration.nix" ] \
   && grep -q 'initialPassword = "password"' "$INSTALLER_DIR/configuration.nix"; then
  gum log --level warn "Default 'password' password may still be active."
  gum confirm "Set a real password now?" && passwd
fi

# rEFInd prompt (taylorpc only)
REFIND_ANSWER="n"
if [[ "$HOST" == "taylorpc" ]]; then
  gum confirm "Configure rEFInd?" && REFIND_ANSWER="y" || REFIND_ANSWER="n"
fi

# Clone or update dotfiles
echo
gum log --level info "Cloning dotfiles..."
if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$REPO" "$DOTFILES_DIR"
else
  gum log --level warn "Dotfiles already exist, pulling latest..."
  git -C "$DOTFILES_DIR" pull --ff-only
fi

if [ ! -d "$HOST_DIR" ]; then
  gum log --level error "Host directory not found: $HOST_DIR"
  gum log --level error "The running hostname '$HOST' has no matching dotfiles host config."
  exit 1
fi

# Generate hardware-configuration.nix directly into /etc/nixos (the default
# --dir for nixos-generate-config, so no flag needed).
gum log --level info "Generating $ETC_NIXOS/hardware-configuration.nix..."
sudo nixos-generate-config --no-filesystems

# Apply dotfiles (puts ~/scripts/* in place so the helpers below resolve)
echo
gum log --level info "Applying dotfiles with chezmoi..."
chezmoi init --source "$DOTFILES_DIR" --apply "$REPO" --force

if [ -x "$HOME/scripts/update-user-dirs.sh" ]; then
  "$HOME/scripts/update-user-dirs.sh"
fi

if [[ "$REFIND_ANSWER" == "y" ]] && [ -x "$HOME/scripts/rEFInd/nix_install-refind.sh" ]; then
  "$HOME/scripts/rEFInd/nix_install-refind.sh"
fi

if [ -x "$HOME/scripts/prepare-secure-boot.sh" ]; then
  "$HOME/scripts/prepare-secure-boot.sh"
fi

# Sync /etc/nixos -> dotfiles
echo
gum log --level info "Syncing per-host files from $ETC_NIXOS -> dotfiles..."
for f in "${SYNC_FILES[@]}"; do
  SRC="$ETC_NIXOS/$f"
  DST="$HOST_DIR/$f"
  if [ ! -f "$SRC" ]; then
    gum log --level warn "  $SRC not found, skipping"
    continue
  fi
  if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then
    continue
  fi
  gum log --level info "  $SRC -> $DST"
  sudo cp -f "$SRC" "$DST"
  sudo chown "$USER:" "$DST"
  git -C "$DOTFILES_DIR" add -f "nixos/hosts/$HOST/$f"
done

# Update flake
gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "Flake Update & Rebuild"

gum log --level info "Updating Nix flake..."
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_DIR/nixos"

# Apply system configuration
echo
gum log --level info "Applying system configuration..."
sudo nixos-rebuild boot --flake "$DOTFILES_DIR/nixos#$HOST"

# Done
echo
gum log --level info "POST-INSTALL SCRIPT COMPLETE."

if gum confirm "Power off now? Enable Secure Boot in your system's BIOS!"; then
  [ -d "$HOME/rEFI2nd" ] && rm -rf "$HOME/rEFI2nd"
  sudo poweroff
fi