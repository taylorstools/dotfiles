#!/usr/bin/env bash

set -euo pipefail
clear

MOUNT_ROOT="/mnt"
LUKS_NAME="rescue-cryptroot"

die() { gum log --level error "$*"; exit 1; }

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS - Fix LUKS UUID Mismatch"

gum style \
  --bold "Must be run from NixOS live ISO!"

# ===== Select partition =====

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

gum confirm "Proceed to check and fix LUKS UUID mismatch?" || { echo "Aborted."; exit 0; }

# ===== Detect and fix LUKS UUID mismatch in hardware-configuration.nix =====

HW_CONFIG="$MOUNT_ROOT/etc/nixos/hardware-configuration.nix"

[[ -f "$HW_CONFIG" ]] || die "Cannot find $HW_CONFIG"

gum log --level info "Inspecting $HW_CONFIG for LUKS UUID mismatch..."

# Extract the LUKS mapper name UUID — the UUID embedded in the attribute name:
#   boot.initrd.luks.devices."luks-XXXXXXXX-...".device = ...
MAPPER_UUID=$(grep -oP 'luks\.devices\."luks-\K[0-9a-f-]+(?="\.)' "$HW_CONFIG" || true)

# Extract the by-uuid path UUID — the UUID in the device path value:
#   ... = "/dev/disk/by-uuid/YYYYYYYY-...";
BYUUID_UUID=$(grep -oP 'luks\.devices\.[^=]+=\s*"/dev/disk/by-uuid/\K[0-9a-f-]+(?=";)' "$HW_CONFIG" || true)

if [[ -z "$MAPPER_UUID" || -z "$BYUUID_UUID" ]]; then
  die "Could not parse LUKS device line from $HW_CONFIG — is this the right config?"
fi

gum style --foreground 39 "  Mapper name UUID : $MAPPER_UUID"
gum style --foreground 39 "  by-uuid path UUID: $BYUUID_UUID"
echo ""

if [[ "$MAPPER_UUID" == "$BYUUID_UUID" ]]; then
  gum log --level info "UUIDs match — no mismatch detected. Nothing to fix."
  gum confirm "Rebuild anyway?" || { echo "Aborted."; exit 0; }
else
  gum log --level warn "UUID MISMATCH DETECTED!"
  gum style --foreground 214 "  The by-uuid path contains '$BYUUID_UUID'"
  gum style --foreground 214 "  but it should match the mapper UUID '$MAPPER_UUID'"
  echo ""
  gum confirm "Fix the mismatch and rebuild?" || { echo "Aborted."; exit 0; }

  gum log --level info "Patching $HW_CONFIG..."

  # Replace only the wrong UUID in the by-uuid device path, leaving everything else untouched
  sudo sed -i "s|/dev/disk/by-uuid/$BYUUID_UUID|/dev/disk/by-uuid/$MAPPER_UUID|g" "$HW_CONFIG"

  # Verify the patch landed correctly
  VERIFY_UUID=$(grep -oP 'luks\.devices\.[^=]+=\s*"/dev/disk/by-uuid/\K[0-9a-f-]+(?=";)' "$HW_CONFIG" || true)
  if [[ "$VERIFY_UUID" == "$MAPPER_UUID" ]]; then
    gum log --level info "Patch applied successfully."
  else
    die "Patch verification failed — please inspect $HW_CONFIG manually."
  fi
fi

# ===== nixos-enter and rebuild =====

gum log --level info "Entering chroot and rebuilding NixOS..."
echo ""

sudo nixos-enter --root "$MOUNT_ROOT" -- bash -c '
  set -euo pipefail
  echo "[*] Rebuilding system..."
  nixos-rebuild boot
  echo ""
  echo "[✓] Done! You can now reboot into your fixed system."
'