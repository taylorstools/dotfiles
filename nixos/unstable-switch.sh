#!/usr/bin/env bash

set -euo pipefail
clear

MOUNT_ROOT="/mnt"
LUKS_NAME="rescue-cryptroot"

die() { gum log --level error "$*"; exit 1; }

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS - Switch to Unstable"

gum style \
  --bold "Must be run from NixOS live ISO!"

# ===== Select partition =====

# Build a list of block devices for gum to display
BLOCK_DEVICES=$(lsblk -lno NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT \
  | awk '$3 == "part" {printf "/dev/%s\t%s\t%s\t%s\n", $1, $2, $4, $5}')

echo
gum log --level info "Select your root partition:"
ROOT_PART=$(echo "$BLOCK_DEVICES" \
  | gum choose --header "Root partition (your encrypted/main OS partition)" \
  | awk '{print $1}')
[[ -b "$ROOT_PART" ]] || die "Not a block device: $ROOT_PART"

gum log --level info "Select your EFI/boot partition:"
BOOT_PART=$(echo "$BLOCK_DEVICES" \
  | grep -v "^$ROOT_PART" \
  | gum choose --header "EFI/boot partition" \
  | awk '{print $1}')
[[ -b "$BOOT_PART" ]] || die "Not a block device: $BOOT_PART"

# ===== Unlock LUKS =====

ROOT_DEV="$ROOT_PART"

if sudo cryptsetup isLuks "$ROOT_PART" 2>/dev/null; then
  gum log --level info "Detected LUKS encryption on $ROOT_PART"

  EXISTING_MAPPER=""
  for dm in /dev/mapper/*; do
    [[ "$(basename "$dm")" == "control" ]] && continue
    if sudo cryptsetup status "$(basename "$dm")" 2>/dev/null \
        | grep -q "$(basename "$ROOT_PART")"; then
      EXISTING_MAPPER="$(basename "$dm")"
      break
    fi
  done

  if [[ -n "$EXISTING_MAPPER" ]]; then
    gum log --level warn "Already mapped as /dev/mapper/$EXISTING_MAPPER, skipping unlock."
    LUKS_NAME="$EXISTING_MAPPER"
  else
    gum log --level info "Unlocking $ROOT_PART..."
    sudo cryptsetup luksOpen "$ROOT_PART" "$LUKS_NAME" \
      || die "Failed to unlock LUKS partition."
    gum log --level info "Unlocked as /dev/mapper/$LUKS_NAME"
  fi
  ROOT_DEV="/dev/mapper/$LUKS_NAME"
fi

# ===== Mount root partition =====

if mountpoint -q "$MOUNT_ROOT" 2>/dev/null || grep -q " $MOUNT_ROOT " /proc/mounts 2>/dev/null; then
  gum log --level warn "$MOUNT_ROOT already mounted, skipping."
else
  gum log --level info "Mounting $ROOT_DEV -> $MOUNT_ROOT"
  sudo mount "$ROOT_DEV" "$MOUNT_ROOT" || die "Failed to mount root partition."
fi

# ===== Mount boot partition =====

BOOT_MOUNT="$MOUNT_ROOT/boot"
sudo mkdir -p "$BOOT_MOUNT"

if mountpoint -q "$BOOT_MOUNT" 2>/dev/null || grep -q " $BOOT_MOUNT " /proc/mounts 2>/dev/null; then
  gum log --level warn "$BOOT_MOUNT already mounted, skipping."
else
  gum log --level info "Mounting $BOOT_PART -> $BOOT_MOUNT"
  sudo mount "$BOOT_PART" "$BOOT_MOUNT" || die "Failed to mount boot partition."
fi

# ===== Summary and confirm =====

echo ""
gum style --foreground 39 "  Root : $ROOT_DEV -> $MOUNT_ROOT"
gum style --foreground 39 "  Boot : $BOOT_PART -> $BOOT_MOUNT"
echo ""

gum confirm "Proceed to nixos-enter and switch to unstable?" || { echo "Aborted."; exit 0; }

# ===== Patch configuration.nix =====
# Logrotate needs to be disabled or else everything dies

NIXOS_CONFIG="$MOUNT_ROOT/etc/nixos/configuration.nix"

if grep -q "logrotate.checkConfig" "$NIXOS_CONFIG"; then
  gum log --level warn "logrotate.checkConfig already set, skipping."
else
  gum log --level info "Disabling logrotate config check in configuration.nix..."
  # Insert before the final closing brace
  sudo sed -i 's/^}$/  services.logrotate.checkConfig = false;\n}/' "$NIXOS_CONFIG"
  gum log --level info "Patched configuration.nix"
fi

# ===== nixos-enter and rebuild =====

gum log --level info "Entering chroot and switching to unstable..."
echo ""

sudo nixos-enter --root "$MOUNT_ROOT" -- bash -c '
  set -euo pipefail
  echo "[*] Adding nixos-unstable channel..."
  nix-channel --add https://nixos.org/channels/nixos-unstable nixos
  echo "[*] Updating channels..."
  nix-channel --update
  echo "[*] Rebuilding system (this may take a while)..."
  nixos-rebuild boot --upgrade
  echo ""
  echo "[✓] Done! You can now reboot into your unstable system."
'