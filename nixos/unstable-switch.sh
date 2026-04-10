#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

MOUNT_ROOT="/mnt"
LUKS_NAME="rescue-cryptroot"

require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)."
}

list_block_devices() {
  echo ""
  info "Available block devices:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null || lsblk
  echo ""
}

prompt() {
  local var="$1" msg="$2" default="${3:-}"
  if [[ -n "$default" ]]; then
    read -rp "$(echo -e "${YELLOW}?${NC} ${msg} [${default}]: ")" "$var"
    [[ -z "${!var}" ]] && eval "$var='$default'"
  else
    read -rp "$(echo -e "${YELLOW}?${NC} ${msg}: ")" "$var"
  fi
}

prompt_yn() {
  local msg="$1" default="${2:-y}"
  local response
  read -rp "$(echo -e "${YELLOW}?${NC} ${msg} [${default}]: ")" response
  response="${response:-$default}"
  [[ "$response" =~ ^[Yy] ]]
}

is_mounted() {
  mountpoint -q "$1" 2>/dev/null || grep -q " $1 " /proc/mounts 2>/dev/null
}

is_luks() {
  cryptsetup isLuks "$1" 2>/dev/null
}

mapper_active() {
  [[ -e "/dev/mapper/$1" ]]
}

# ── Main ──────────────────────────────────────────────────────────────────────

require_root
list_block_devices

echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}   NixOS Rescue — Switch to Unstable   ${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# ── Root partition ────────────────────────────────────────────────────────────

prompt ROOT_PART "Root partition (e.g. /dev/sda2, /dev/nvme0n1p2)"
[[ -b "$ROOT_PART" ]] || die "Not a block device: $ROOT_PART"

LUKS_ENCRYPTED=false
if is_luks "$ROOT_PART"; then
  LUKS_ENCRYPTED=true
  info "Detected LUKS encryption on $ROOT_PART"
fi

# ── EFI / boot partition ──────────────────────────────────────────────────────

prompt BOOT_PART "EFI/boot partition (e.g. /dev/sda1, /dev/nvme0n1p1)"
[[ -b "$BOOT_PART" ]] || die "Not a block device: $BOOT_PART"

# ── Unlock LUKS if needed ─────────────────────────────────────────────────────

ROOT_DEV="$ROOT_PART"

if $LUKS_ENCRYPTED; then
  if mapper_active "$LUKS_NAME"; then
    warn "LUKS mapper /dev/mapper/$LUKS_NAME already exists, skipping unlock."
  else
    info "Unlocking LUKS partition $ROOT_PART..."
    cryptsetup luksOpen "$ROOT_PART" "$LUKS_NAME" \
      || die "Failed to unlock LUKS partition."
    success "Unlocked as /dev/mapper/$LUKS_NAME"
  fi
  ROOT_DEV="/dev/mapper/$LUKS_NAME"
fi

# ── Mount root ────────────────────────────────────────────────────────────────

if is_mounted "$MOUNT_ROOT"; then
  warn "$MOUNT_ROOT is already mounted, skipping."
else
  info "Mounting $ROOT_DEV -> $MOUNT_ROOT"
  mount "$ROOT_DEV" "$MOUNT_ROOT" \
    || die "Failed to mount root partition."
  success "Mounted root."
fi

# ── Mount boot ────────────────────────────────────────────────────────────────

BOOT_MOUNT="$MOUNT_ROOT/boot"
mkdir -p "$BOOT_MOUNT"

if is_mounted "$BOOT_MOUNT"; then
  warn "$BOOT_MOUNT is already mounted, skipping."
else
  info "Mounting $BOOT_PART -> $BOOT_MOUNT"
  mount "$BOOT_PART" "$BOOT_MOUNT" \
    || die "Failed to mount boot partition."
  success "Mounted boot."
fi

# ── Confirm before entering ───────────────────────────────────────────────────

echo ""
echo -e "  Root : ${GREEN}$ROOT_DEV${NC} -> ${GREEN}$MOUNT_ROOT${NC}"
echo -e "  Boot : ${GREEN}$BOOT_PART${NC} -> ${GREEN}$BOOT_MOUNT${NC}"
echo ""

prompt_yn "Proceed to nixos-enter and switch to unstable?" "y" \
  || { warn "Aborted."; exit 0; }

# ── nixos-enter and rebuild ───────────────────────────────────────────────────

info "Entering chroot and switching to unstable..."
echo ""

nixos-enter --root "$MOUNT_ROOT" -- bash -c '
  set -euo pipefail
  echo "[*] Adding nixos-unstable channel..."
  nix-channel --add https://nixos.org/channels/nixos-unstable nixos
  echo "[*] Updating channels..."
  nix-channel --update
  echo "[*] Rebuilding system (this may take a while)..."
  nixos-rebuild switch --upgrade
  echo ""
  echo "[✓] Done! You can now reboot into your unstable system."
'