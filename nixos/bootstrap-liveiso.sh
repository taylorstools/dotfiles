#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root on the live ISO."
  exit 1
fi

MOUNT_POINT="/mnt"
REPO="https://github.com/taylorstools/dotfiles"
GREEN=$'\e[32m'
RESET=$'\e[0m'

# ---------------------------------------------------------------------------
# Unmount on exit (including error/ctrl-c). Suppressed on clean reboot path.
# ---------------------------------------------------------------------------
cleanup() {
  echo
  echo "Cleaning up mounts..."
  umount -R "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Show available block devices and prompt for partitions
# ---------------------------------------------------------------------------
echo "Available block devices:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo

read -rp "Enter the root partition (e.g. /dev/sda2, /dev/nvme0n1p2): " ROOT_PART

read -rp "Enter the EFI/boot partition (leave blank to skip): " EFI_PART
EFI_PART="${EFI_PART:-}"

read -rp "EFI mount point inside the system [/boot]: " EFI_MOUNT_REL
EFI_MOUNT_REL="${EFI_MOUNT_REL:-/boot}"

# ---------------------------------------------------------------------------
# Unlock LUKS if the root partition is encrypted
# ---------------------------------------------------------------------------
LUKS_NAME="cryptroot"
MOUNT_SOURCE="$ROOT_PART"

if cryptsetup isLuks "$ROOT_PART" 2>/dev/null; then
  echo
  echo -e "${GREEN}LUKS encryption detected on $ROOT_PART.${RESET}"

  # Check if the partition is already open under any mapper name
  EXISTING_MAPPING=$(dmsetup deps -o devname 2>/dev/null \
    | awk -F'[: ()]' -v dev="$(basename "$ROOT_PART")" \
        '$0 ~ dev { print $1 }' | head -n1)

  if [ -n "$EXISTING_MAPPING" ]; then
    echo "Partition is already unlocked as /dev/mapper/$EXISTING_MAPPING, re-using it."
    LUKS_NAME="$EXISTING_MAPPING"
  else
    cryptsetup luksOpen "$ROOT_PART" "$LUKS_NAME"
  fi

  MOUNT_SOURCE="/dev/mapper/$LUKS_NAME"

  # Close the LUKS device after unmounting in cleanup
  cleanup() {
    echo
    echo "Cleaning up mounts..."
    umount -R "$MOUNT_POINT" 2>/dev/null || true
    cryptsetup luksClose "$LUKS_NAME" 2>/dev/null || true
  }
  trap cleanup EXIT
fi

# ---------------------------------------------------------------------------
# Mount the installed system
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Mounting $MOUNT_SOURCE -> $MOUNT_POINT...${RESET}"
mount "$MOUNT_SOURCE" "$MOUNT_POINT"

if [ -n "$EFI_PART" ]; then
  EFI_MOUNT_ABS="$MOUNT_POINT$EFI_MOUNT_REL"
  mkdir -p "$EFI_MOUNT_ABS"
  echo -e "${GREEN}Mounting $EFI_PART -> $EFI_MOUNT_ABS...${RESET}"
  mount "$EFI_PART" "$EFI_MOUNT_ABS"
fi

# ---------------------------------------------------------------------------
# Detect normal (UID >= 1000) users on the installed system and pick one
# ---------------------------------------------------------------------------
echo
echo "Users found on the installed system:"
awk -F: '$3 >= 1000 && $3 < 65534 { print "  " $1 }' "$MOUNT_POINT/etc/passwd"
echo

read -rp "Enter your username on the installed system: " USERNAME

# Resolve UID/GID so we can fix ownership after git operations
USER_UID=$(awk -F: -v u="$USERNAME" '$1 == u { print $3 }' "$MOUNT_POINT/etc/passwd")
USER_GID=$(awk -F: -v u="$USERNAME" '$1 == u { print $4 }' "$MOUNT_POINT/etc/passwd")

if [ -z "$USER_UID" ]; then
  echo "Error: User '$USERNAME' not found in the installed system's /etc/passwd."
  exit 1
fi

# Paths from the live ISO's perspective and from inside the chroot
DOTFILES_HOST="$MOUNT_POINT/home/$USERNAME/.dotfiles"
DOTFILES_CHROOT="/home/$USERNAME/.dotfiles"

# ---------------------------------------------------------------------------
# Clone / update dotfiles directly into the mounted home directory
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Cloning dotfiles...${RESET}"
if [ ! -d "$DOTFILES_HOST" ]; then
  git clone "$REPO" "$DOTFILES_HOST"
else
  echo "Dotfiles already exist, pulling latest..."
  git -C "$DOTFILES_HOST" pull
fi
chown -R "$USER_UID:$USER_GID" "$DOTFILES_HOST"

# ---------------------------------------------------------------------------
# Choose host configuration
# ---------------------------------------------------------------------------
hosts=()
for dir in "$DOTFILES_HOST/nixos/hosts"/*/; do
  [ -d "$dir" ] || continue
  hosts+=("$(basename "$dir")")
done

if [ "${#hosts[@]}" -eq 0 ]; then
  echo "Error: No host configurations found in dotfiles."
  exit 1
fi

echo
if command -v gum &>/dev/null; then
  HOST=$(printf "%s\n" "${hosts[@]}" | gum choose --header "Choose the host for this configuration:")
else
  echo "Available hosts:"
  select HOST in "${hosts[@]}"; do
    [ -n "$HOST" ] && break
    echo "Invalid selection, try again."
  done
fi

[ -z "$HOST" ] && { echo; echo "No host selected."; exit 1; }

# ---------------------------------------------------------------------------
# Optional: rEFInd (taylorpc only)
# ---------------------------------------------------------------------------
REFIND_ANSWER="n"
if [[ "$HOST" == "taylorpc" ]]; then
  read -rp "${GREEN}Do you want to configure rEFInd? [Y/n]:${RESET} " REFIND_ANSWER
  REFIND_ANSWER="${REFIND_ANSWER:-y}"
fi

# ---------------------------------------------------------------------------
# Copy hardware-configuration.nix from the installed system into dotfiles
# ---------------------------------------------------------------------------
HW_CFG="$MOUNT_POINT/etc/nixos/hardware-configuration.nix"
if [ -f "$HW_CFG" ]; then
  echo
  echo -e "${GREEN}Copying hardware-configuration.nix...${RESET}"
  cp -f "$HW_CFG" "$DOTFILES_HOST/nixos/hosts/$HOST/hardware-configuration.nix"
  chown "$USER_UID:$USER_GID" "$DOTFILES_HOST/nixos/hosts/$HOST/hardware-configuration.nix"
else
  echo "Warning: /etc/nixos/hardware-configuration.nix not found on installed system — skipping."
fi

# ---------------------------------------------------------------------------
# Helper: run a command as the target user inside the chroot.
# nixos-enter automatically bind-mounts /proc, /sys, /dev, etc.
# runuser is used instead of su — it doesn't require PAM authentication,
# which is unavailable inside a chroot.
# ---------------------------------------------------------------------------
run_as_user() {
  nixos-enter --root "$MOUNT_POINT" -- \
    runuser -l "$USERNAME" -c "$*"
}

# ---------------------------------------------------------------------------
# Update the Nix flake from the live ISO directly — no chroot needed,
# and avoids daemon/auth issues. DOTFILES_HOST is the path on the ISO side.
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Updating Nix flake...${RESET}"
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_HOST/nixos"

# ---------------------------------------------------------------------------
# Apply system configuration (nixos-rebuild must run as root in the chroot)
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Applying system configuration...${RESET}"
nixos-enter --root "$MOUNT_POINT" -- \
  nixos-rebuild switch --flake "$DOTFILES_CHROOT/nixos#$HOST" \
    --option sandbox false

# ---------------------------------------------------------------------------
# Apply dotfiles with chezmoi (as user)
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Applying dotfiles with chezmoi...${RESET}"
run_as_user "chezmoi init --apply '$DOTFILES_CHROOT' --force"

# ---------------------------------------------------------------------------
# Run remaining user-level scripts from the installed system
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Setting user directories...${RESET}"
run_as_user "\$HOME/scripts/update-user-dirs.sh"

echo
run_as_user "\$HOME/scripts/luks-tpm-autounlock.sh --hostname '$HOST'"

case "$REFIND_ANSWER" in
  [yY]|[yY][eE][sS])
    echo
    echo -e "${GREEN}Configuring rEFInd...${RESET}"
    run_as_user "\$HOME/scripts/rEFInd/nix_install-refind.sh"
    ;;
esac

# ---------------------------------------------------------------------------
# Pre-reboot cleanup inside the mounted system
# ---------------------------------------------------------------------------
REFI2ND="$MOUNT_POINT/home/$USERNAME/rEFI2nd"
[ -d "$REFI2ND" ] && rm -rf "$REFI2ND"
[ -d "$MOUNT_POINT/etc/nixos" ] && rm -rf "$MOUNT_POINT/etc/nixos"

# ---------------------------------------------------------------------------
# Optionally reboot
# ---------------------------------------------------------------------------
echo
echo -e "${GREEN}Done!${RESET}"
read -rp "Do you want to reboot now? [Y/n]: " REBOOT_ANSWER
REBOOT_ANSWER="${REBOOT_ANSWER:-y}"

case "$REBOOT_ANSWER" in
  [yY]|[yY][eE][sS])
    # Disable the cleanup trap — we unmount and close LUKS explicitly before rebooting
    trap - EXIT
    umount -R "$MOUNT_POINT" 2>/dev/null || true
    cryptsetup luksClose "$LUKS_NAME" 2>/dev/null || true
    reboot
    ;;
  *)
    # Let the trap handle unmounting
    ;;
esac