#!/usr/bin/env bash

set -euo pipefail
clear

# ===== Sanity checks =====

if [ "$(id -u)" -ne 0 ]; then
  gum log --level error "This script must be run as root (it partitions disks and runs nixos-install)."
  gum log --level error "Try: sudo nix run github:taylorstools/dotfiles?dir=nixos#bootstrap-minimal --extra-experimental-features 'nix-command flakes'"
  exit 1
fi

if ! curl -s --max-time 5 -o /dev/null https://github.com; then
  gum log --level error "No internet access. Bring up networking (nmtui / wpa_supplicant / DHCP) and re-run."
  exit 1
fi

REPO="https://github.com/taylorstools/dotfiles"
MOUNT_POINT="/mnt"
TMP_DOTFILES="/tmp/dotfiles"

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS Minimal Install Bootstrap"

# ===== Clean up any prior attempt =====

gum log --level info "Cleaning up any prior mounts under $MOUNT_POINT..."
umount -R "$MOUNT_POINT" 2>/dev/null || true
swapoff -a 2>/dev/null || true
if [ -e /dev/mapper/cryptroot ]; then
  cryptsetup close cryptroot 2>/dev/null || true
fi

# ===== Select disk =====

echo
gum log --level info "Detecting available disks..."

mapfile -t DISK_LINES < <(lsblk -dn -o NAME,SIZE,MODEL -e 7,11)
if [ ${#DISK_LINES[@]} -eq 0 ]; then
  gum log --level error "No disks found."
  exit 1
fi

DISK_OPTIONS=()
for line in "${DISK_LINES[@]}"; do
  Name=$(echo "$line"  | awk '{print $1}')
  Size=$(echo "$line"  | awk '{print $2}')
  Model=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}' | sed 's/ *$//')
  [ -z "$Model" ] && Model="(no model)"
  DISK_OPTIONS+=("/dev/$Name  $Size  $Model")
done

DISK_SELECTION=$(printf "%s\n" "${DISK_OPTIONS[@]}" | gum choose --header "Select target disk (will be partitioned):")
[ -z "$DISK_SELECTION" ] && { gum log --level error "No disk selected."; exit 1; }
DISK=$(echo "$DISK_SELECTION" | awk '{print $1}')

gum log --level warn "Target disk: $DISK"
gum confirm "All data on $DISK may be destroyed. Continue?" || exit 1

# ===== Optionally wipe + fresh GPT =====

WipeGpt="n"
if gum confirm "Wipe existing partition table and create a fresh GPT? (recommended for a clean install)"; then
  WipeGpt="y"
fi

if [ "$WipeGpt" = "y" ]; then
  gum log --level info "Zapping existing partition table and creating fresh GPT on $DISK..."
  sgdisk --zap-all "$DISK" >/dev/null
  sgdisk -o      "$DISK" >/dev/null
  partprobe "$DISK" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
fi

# ===== Run cgdisk =====

echo
gum style --foreground 39 --bold "Launching cgdisk on $DISK"
gum log --level info "Create at minimum:"
gum log --level info "  - an EFI System Partition (~1G, type 'EF00')"
gum log --level info "  - a Linux partition for root (LUKS configured next, optional)"
gum log --level info "Optional: a swap partition (type '8200')."
gum log --level info "Use [ New ] for each, then [ Write ] -> 'yes', then [ Quit ]."
sleep 3
cgdisk "$DISK"

partprobe "$DISK" 2>/dev/null || true
udevadm settle 2>/dev/null || true
sleep 1

# ===== Select partitions =====

mapfile -t PART_LINES < <(lsblk -ln -o NAME,SIZE,TYPE "$DISK" | awk '$3 == "part"')

if [ ${#PART_LINES[@]} -lt 2 ]; then
  gum log --level error "Need at least 2 partitions (EFI + root). Found ${#PART_LINES[@]}."
  exit 1
fi

PART_OPTIONS=()
for line in "${PART_LINES[@]}"; do
  Name=$(echo "$line" | awk '{print $1}')
  Size=$(echo "$line" | awk '{print $2}')
  PART_OPTIONS+=("/dev/$Name  $Size")
done

echo
gum log --level info "Select EFI/boot partition:"
EfiSelection=$(printf "%s\n" "${PART_OPTIONS[@]}" | gum choose --header "EFI System Partition (will be FAT32):")
EFI_PART=$(echo "$EfiSelection" | awk '{print $1}')

echo
gum log --level info "Select root partition:"
RootSelection=$(printf "%s\n" "${PART_OPTIONS[@]}" | gum choose --header "Root partition (will be ext4, optionally LUKS):")
ROOT_PART=$(echo "$RootSelection" | awk '{print $1}')

if [ "$EFI_PART" = "$ROOT_PART" ]; then
  gum log --level error "EFI and root partitions cannot be the same."
  exit 1
fi

SWAP_PART=""
if gum confirm "Do you have a swap partition to use?"; then
  SwapSelection=$(printf "%s\n" "${PART_OPTIONS[@]}" | gum choose --header "Swap partition:")
  SWAP_PART=$(echo "$SwapSelection" | awk '{print $1}')
  if [ "$SWAP_PART" = "$EFI_PART" ] || [ "$SWAP_PART" = "$ROOT_PART" ]; then
    gum log --level error "Swap must be distinct from EFI and root."
    exit 1
  fi
fi

# ===== LUKS prompt =====

UseLuks="n"
if gum confirm "Encrypt the root partition with LUKS?"; then
  UseLuks="y"
fi

# ===== Clone dotfiles to /tmp to read host list =====

echo
gum log --level info "Cloning dotfiles to $TMP_DOTFILES..."
rm -rf "$TMP_DOTFILES"
git clone --depth=1 "$REPO" "$TMP_DOTFILES"

Hosts=()
for dir in "$TMP_DOTFILES/nixos/hosts"/*/; do
  [ -d "$dir" ] || continue
  Hosts+=("$(basename "$dir")")
done

if [ ${#Hosts[@]} -eq 0 ]; then
  gum log --level error "No hosts found in $TMP_DOTFILES/nixos/hosts."
  exit 1
fi

echo
gum log --level info "Select host configuration:"
HOST=$(printf "%s\n" "${Hosts[@]}" | gum choose --header "Choose the host for this configuration:")
[ -z "$HOST" ] && { gum log --level error "No host selected."; exit 1; }

# ===== rEFInd prompt (taylorpc only, matches existing bootstrap.sh) =====

REFIND_ANSWER="n"
if [[ "$HOST" == "taylorpc" ]]; then
  echo
  if gum confirm "Configure rEFInd?"; then
    REFIND_ANSWER="y"
  fi
fi

# ===== Username prompt =====

echo
USERNAME=$(gum input --header "Enter the primary username on this system (used by chezmoi and post-install scripts):" --placeholder "username")
[ -z "$USERNAME" ] && { gum log --level error "No username provided."; exit 1; }

# ===== Final summary + confirm =====

echo
Summary="Plan:
  Disk:    $DISK
  EFI:     $EFI_PART (FAT32, label 'boot')
  Root:    $ROOT_PART$( [ "$UseLuks" = "y" ] && echo " -> LUKS2 -> ext4 'nixos'" || echo " (ext4, label 'nixos')")"
[ -n "$SWAP_PART" ] && Summary="$Summary
  Swap:    $SWAP_PART (label 'swap')"
Summary="$Summary
  Host:    $HOST
  User:    $USERNAME
  rEFInd:  $REFIND_ANSWER"

gum style --border normal --padding "1 2" --foreground 196 "$Summary"
gum confirm "Proceed with install?" || exit 1

# ===== Format =====

echo
gum log --level info "Formatting EFI partition as FAT32..."
mkfs.fat -F 32 -n boot "$EFI_PART"

if [ -n "$SWAP_PART" ]; then
  gum log --level info "Initializing swap..."
  mkswap -L swap "$SWAP_PART"
  swapon "$SWAP_PART"
fi

ROOT_DEV="$ROOT_PART"
if [ "$UseLuks" = "y" ]; then
  gum log --level info "Setting up LUKS on $ROOT_PART (you'll be prompted for the passphrase)..."
  cryptsetup luksFormat --type luks2 "$ROOT_PART"
  gum log --level info "Opening LUKS volume as 'cryptroot'..."
  cryptsetup open "$ROOT_PART" cryptroot
  ROOT_DEV="/dev/mapper/cryptroot"
fi

gum log --level info "Formatting root as ext4..."
mkfs.ext4 -L nixos "$ROOT_DEV"

# ===== Mount =====

gum log --level info "Mounting partitions..."
mount "$ROOT_DEV" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/boot"
mount -o umask=077 "$EFI_PART" "$MOUNT_POINT/boot"

# ===== Generate hardware-configuration.nix =====

echo
gum log --level info "Generating hardware-configuration.nix..."
nixos-generate-config --root "$MOUNT_POINT"

# ===== Move dotfiles into installed system =====

DOTFILES_DIR="$MOUNT_POINT/root/.dotfiles"
gum log --level info "Moving dotfiles to $DOTFILES_DIR..."
mkdir -p "$MOUNT_POINT/root"
mv "$TMP_DOTFILES" "$DOTFILES_DIR"

# ===== Copy hardware-configuration.nix into dotfiles =====

gum log --level info "Copying hardware-configuration.nix into dotfiles..."
cp -f \
  "$MOUNT_POINT/etc/nixos/hardware-configuration.nix" \
  "$DOTFILES_DIR/nixos/hosts/$HOST/hardware-configuration.nix"

git -C "$DOTFILES_DIR" add --intent-to-add -f \
  "nixos/hosts/$HOST/hardware-configuration.nix"

# ===== Update flake =====

gum log --level info "Updating Nix flake..."
nix --extra-experimental-features "nix-command flakes" \
  flake update --flake "$DOTFILES_DIR/nixos"

# ===== nixos-install =====

echo
gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "Running nixos-install"
gum log --level info "You will be prompted to set the root password..."
nixos-install \
  --root  "$MOUNT_POINT" \
  --flake "$DOTFILES_DIR/nixos#$HOST"

# ===== Set password for the regular user =====

echo
if gum confirm "Set a password for $USERNAME now? (recommended; chezmoi/sudo will need it)"; then
  nixos-enter --root "$MOUNT_POINT" --command "passwd $USERNAME"
fi

# ===== Post-install steps via nixos-enter =====

echo
gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "Post-install: chezmoi, TPM, user dirs, rEFInd"

# Drop a runner into the new system, then exec it as the user via nixos-enter.
# Variables expanded HERE: $HOST, $REPO, $REFIND_ANSWER -- written into the file.
# Variables escaped (\$...): evaluated INSIDE the new system at runtime.
cat > "$MOUNT_POINT/tmp/post-install.sh" <<POSTEOF
#!/usr/bin/env bash
set -euo pipefail

HOST="$HOST"
REPO="$REPO"
DO_REFIND="$REFIND_ANSWER"

echo ">>> Applying dotfiles via chezmoi..."
chezmoi init --apply --force "\${REPO}"

if [ -x "\${HOME}/scripts/luks-tpm-autounlock.sh" ]; then
  echo ">>> Setting up LUKS TPM autounlock..."
  bash "\${HOME}/scripts/luks-tpm-autounlock.sh" --hostname "\${HOST}"
else
  echo ">>> Skipping luks-tpm-autounlock.sh (not present or not executable)."
fi

if [ -x "\${HOME}/scripts/update-user-dirs.sh" ]; then
  echo ">>> Updating user directories..."
  bash "\${HOME}/scripts/update-user-dirs.sh"
else
  echo ">>> Skipping update-user-dirs.sh (not present or not executable)."
fi

if [[ "\${DO_REFIND}" == "y" ]]; then
  if [ -x "\${HOME}/scripts/rEFInd/nix_install-refind.sh" ]; then
    echo ">>> Installing rEFInd..."
    bash "\${HOME}/scripts/rEFInd/nix_install-refind.sh"
  else
    echo ">>> rEFInd installer not found; skipping."
  fi
fi

echo ">>> Post-install complete."
POSTEOF
chmod 755 "$MOUNT_POINT/tmp/post-install.sh"

gum log --level info "Entering the new system to run post-install steps as $USERNAME..."
nixos-enter --root "$MOUNT_POINT" --command "su -l '$USERNAME' -c '/tmp/post-install.sh'"
rm -f "$MOUNT_POINT/tmp/post-install.sh"

# ===== Done =====

echo
gum log --level info "BOOTSTRAP COMPLETE."

if gum confirm "Reboot now?"; then
  swapoff -a 2>/dev/null || true
  umount -R "$MOUNT_POINT" 2>/dev/null || true
  if [ "$UseLuks" = "y" ]; then
    cryptsetup close cryptroot 2>/dev/null || true
  fi
  reboot
fi
