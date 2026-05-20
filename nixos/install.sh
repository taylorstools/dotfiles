#!/usr/bin/env bash
set -euo pipefail

# Re-exec as root if not
if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E "$0" "$@"
fi

clear

REPO_OWNER="taylorstools"
REPO_NAME="dotfiles"
HOSTS_PATH="nixos/hosts"
WORK="/tmp/install"

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS Install Script"

# Choose target disk for NixOS install
gum log --level info "Detected disks:"
echo
lsblk -dpno NAME,SIZE,TRAN,MODEL,TYPE | awk '$NF=="disk"{$NF=""; print}'
echo

mapfile -t DISK_LINES < <(
  lsblk -dpno NAME,SIZE,TRAN,MODEL,TYPE | awk '$NF=="disk"{
    name=$1; size=$2; tran=$3;
    $1=""; $2=""; $3=""; $NF="";
    gsub(/^ +| +$/,""); gsub(/ +/," ");
    printf "%s  %s  %s  %s\n", name, size, tran, $0
  }'
)
DISK_CHOICE=$(printf "%s\n" "${DISK_LINES[@]}" \
  | gum choose --header "Target disk:")
[ -z "$DISK_CHOICE" ] && { gum log --level error "No disk selected."; exit 1; }
DISK_DEV=$(echo "$DISK_CHOICE" | awk '{print $1}')

# Resolve to a stable /dev/disk/by-id/ path (skip wwn-* unless nothing else)
DISK_BY_ID=""
WWN_FALLBACK=""
for link in /dev/disk/by-id/*; do
  [ -L "$link" ] || continue
  [ "$(readlink -f "$link")" = "$DISK_DEV" ] || continue
  case "$link" in
    */wwn-*|*/eui.*) [ -z "$WWN_FALLBACK" ] && WWN_FALLBACK="$link" ;;
    *)               DISK_BY_ID="$link"; break ;;
  esac
done
DISK="${DISK_BY_ID:-${WWN_FALLBACK:-$DISK_DEV}}"
gum log --level info "Using disk path: $DISK"

# Pick hostname from dotfiles hosts directory on GitHub
gum log --level info "Fetching host list from GitHub..."
mapfile -t HOSTS < <(
  curl -sfL "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$HOSTS_PATH" \
    | jq -r '.[] | select(.type=="dir") | .name'
)
if [ "${#HOSTS[@]}" -eq 0 ]; then
  gum log --level error "Couldn't fetch host list from GitHub."
  exit 1
fi

HOSTNAME=$(printf "%s\n" "${HOSTS[@]}" | gum choose --header "Select host:")
[ -z "$HOSTNAME" ] && { gum log --level error "No host selected."; exit 1; }

# Disk strategy (taylorpc only)
LUKS_SIZE="100%"
WIPE=true
DISKO_MODE="disko"

if [[ "$HOSTNAME" == "taylorpc" ]]; then
  echo
  if gum confirm "Plan on dual-booting Windows on this drive?"; then
    STRATEGY=$(gum choose --header "How should NixOS be placed?" \
      "Wipe drive (allocate a percentage of the disk to NixOS)" \
      "Install to existing unallocated space (preserve existing partitions)")

    case "$STRATEGY" in
      "Wipe drive"*)
        while :; do
          PCT=$(gum input \
            --header "Percentage of $DISK to use for NixOS (1-100):" \
            --value "25" --placeholder "1-100")
          [ -z "$PCT" ] && PCT=25
          PCT="${PCT%\%}"
          if [[ "$PCT" =~ ^[0-9]+$ ]] && [ "$PCT" -ge 1 ] && [ "$PCT" -le 100 ]; then
            break
          fi
          gum log --level warn "Enter a whole number between 1 and 100."
        done

        if [ "$PCT" -eq 100 ]; then
          LUKS_SIZE="100%"
          gum log --level info "LUKS will use 100% of $DISK."
        else
          DISK_BYTES=$(blockdev --getsize64 "$DISK")
          LUKS_GIB=$(( DISK_BYTES * PCT / 100 / 1024 / 1024 / 1024 ))
          if [ "$LUKS_GIB" -lt 1 ]; then
            gum log --level error "Computed LUKS size (${LUKS_GIB}G) is too small; pick a larger percentage."
            exit 1
          fi
          LUKS_SIZE="${LUKS_GIB}G"
          gum log --level info "LUKS will use ${LUKS_SIZE} (${PCT}%) of $DISK; the rest stays unallocated."
        fi
        ;;
      "Install to existing unallocated space"*)
        WIPE=false
        DISKO_MODE="format"
        LUKS_SIZE="100%"
        gum log --level info "NixOS will be placed in the largest unallocated region; existing partitions preserved."
        ;;
    esac
  fi
fi

# Generate ZFS hostId
HOSTID=$(head -c4 /dev/urandom | od -A none -tx4 | tr -d ' ')
gum log --level info "Generated networking.hostId = $HOSTID"

# Brand the live ISO with the chosen hostId
# So the ZFS pool gets created with the same hostId we bake into the config.
gum log --level info "Setting /etc/hostid on live ISO to $HOSTID..."
rm -f /etc/hostid
if command -v zgenhostid >/dev/null; then
  zgenhostid -f "$HOSTID"
else
  printf '%b' "\x${HOSTID:6:2}\x${HOSTID:4:2}\x${HOSTID:2:2}\x${HOSTID:0:2}" \
    > /etc/hostid
fi

got=$(hostid)
[ "$got" = "$HOSTID" ] || gum log --level warn "hostid reports '$got', expected '$HOSTID', proceeding anyway"

# Stage configs with substitutions
STAGE="$WORK/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"

sed -e "s|@DISK@|$DISK|g" -e "s|@LUKS_SIZE@|$LUKS_SIZE|g" \
    "$DISKO_TEMPLATE" > "$STAGE/disko.nix"
sed -e "s|@HOSTNAME@|$HOSTNAME|g" -e "s|@HOSTID@|$HOSTID|g" \
    "$CONFIG_TEMPLATE" > "$STAGE/configuration.nix"
cp "$FLAKE_TEMPLATE" "$STAGE/flake.nix"

# Disko optional review to user
echo
if gum confirm "Review/edit disko.nix?" --default=No; then
  ${EDITOR:-nano} "$STAGE/disko.nix"
fi

# LUKS passphrase (written to a file disko can read)
gum log --level info "Set the LUKS passphrase for this install."
while :; do
  LUKS_PASS=$(gum input --password --header "LUKS passphrase:")
  [ -z "$LUKS_PASS" ] && { gum log --level error "Passphrase can't be empty."; continue; }
  LUKS_CONFIRM=$(gum input --password --header "Confirm passphrase:")
  [ "$LUKS_PASS" = "$LUKS_CONFIRM" ] && break
  gum log --level warn "Passphrases didn't match; try again."
done

install -d -m 0700 /tmp/install
printf '%s' "$LUKS_PASS" > /tmp/install/luks.key
chmod 600 /tmp/install/luks.key
unset LUKS_PASS LUKS_CONFIRM
trap 'shred -u /tmp/install/luks.key 2>/dev/null || rm -f /tmp/install/luks.key' EXIT

# User password (hashed; never enters the nix store)
gum log --level info "Set the password for the 'taylor' user."
while :; do
  USER_PASS=$(gum input --password --header "User password:")
  [ -z "$USER_PASS" ] && { gum log --level error "Password can't be empty."; continue; }
  USER_CONFIRM=$(gum input --password --header "Confirm password:")
  [ "$USER_PASS" = "$USER_CONFIRM" ] && break
  gum log --level warn "Passwords didn't match; try again."
done

USER_HASH=$(printf '%s' "$USER_PASS" | mkpasswd -m yescrypt -s)
unset USER_PASS USER_CONFIRM

# Final confirmation
echo
gum style --foreground 196 --bold "DESTRUCTIVE OPERATION!"
gum log --level warn "Disk:     $DISK"
gum log --level warn "Hostname: $HOSTNAME"
gum log --level warn "HostId:   $HOSTID"
if [ "$WIPE" = true ]; then
  gum log --level warn "Action:   wipe entire disk"
  gum log --level warn "LUKS:     $LUKS_SIZE of disk"
else
  gum log --level warn "Action:   install to largest unallocated region (existing partitions preserved)"
fi
echo

if [ "$WIPE" = true ]; then
  CONFIRM_PROMPT="Wipe $DISK and install?"
else
  CONFIRM_PROMPT="Install NixOS to unallocated space on $DISK?"
fi
gum confirm "$CONFIRM_PROMPT" \
  --affirmative "Yes, proceed" --negative "Abort" \
  || { gum log --level error "Aborted."; exit 1; }

# Prepare disk
if [ "$WIPE" = true ]; then
  # Full disk wipe
  gum log --level info "Wiping $DISK..."
  umount -R /mnt 2>/dev/null || true
  zpool labelclear -f "$DISK" 2>/dev/null || true

  if ! blkdiscard -f "$DISK" 2>/dev/null; then
    gum log --level warn "blkdiscard unsupported, falling back to zero-write."
    dd if=/dev/zero of="$DISK" bs=1M count=2048 conv=fsync status=progress
  fi

  wipefs -af "$DISK" || true
  sgdisk --zap-all "$DISK" || true
  partprobe "$DISK" || true
  udevadm settle || true
  sleep 2

  gum log --level info "Post-wipe signatures (should be empty):"
  if blkid "$DISK"* 2>/dev/null | tee /dev/stderr | grep -q .; then
    gum log --level error "Wipe failed, signatures still present. Aborting."
    exit 1
  fi
  gum log --level info "Disk is clean."
else
  # Carve partitions out of unallocated space; leave existing partitions alone.
  gum log --level info "Locating largest unallocated region on $DISK..."
  umount -R /mnt 2>/dev/null || true
  zpool labelclear -f "$DISK" 2>/dev/null || true

  # Idempotency: if a previous failed run left disk-main-ESP / disk-main-luks
  # partitions on disk, delete them so this run starts from a clean slate.
  for label in disk-main-ESP disk-main-luks; do
    if [ -e "/dev/disk/by-partlabel/$label" ]; then
      OLD_PART=$(readlink -f "/dev/disk/by-partlabel/$label")
      OLD_NUM=$(echo "$OLD_PART" | grep -oE '[0-9]+$')
      if [ -n "$OLD_NUM" ]; then
        gum log --level info "Removing stale partition $label (number $OLD_NUM)..."
        sgdisk --delete="$OLD_NUM" "$DISK" || true
      fi
    fi
  done
  partprobe "$DISK" || true
  udevadm settle || true

  # Find the largest contiguous free range.
  FREE_INFO=$(sgdisk --first-in-largest --end-of-largest "$DISK" 2>&1) || {
    gum log --level error "sgdisk failed to query free space on $DISK:"
    gum log --level error "$FREE_INFO"
    exit 1
  }
  FREE_FIRST=$(echo "$FREE_INFO" | sed -n '1p')
  FREE_LAST=$(echo "$FREE_INFO" | sed -n '2p')

  if ! [[ "$FREE_FIRST" =~ ^[0-9]+$ ]] || ! [[ "$FREE_LAST" =~ ^[0-9]+$ ]]; then
    gum log --level error "Could not parse sgdisk output: $FREE_INFO"
    exit 1
  fi

  SECTOR=$(blockdev --getss "$DISK")
  FREE_BYTES=$(( (FREE_LAST - FREE_FIRST + 1) * SECTOR ))
  FREE_GIB=$(( FREE_BYTES / 1024 / 1024 / 1024 ))
  if [ "$FREE_GIB" -lt 16 ]; then
    gum log --level error "Only ${FREE_GIB} GiB unallocated; need at least 16 GiB."
    exit 1
  fi
  gum log --level info "Found ${FREE_GIB} GiB of unallocated space (sectors ${FREE_FIRST}-${FREE_LAST})."

  # Create ESP (1G) and LUKS (rest of free region) with partlabels disko expects.
  # `--new=0:...` lets sgdisk pick the next available partition number.
  sgdisk \
    --new="0:${FREE_FIRST}:+1G" \
    --typecode=0:EF00 \
    --change-name=0:disk-main-ESP \
    --new="0:0:${FREE_LAST}" \
    --typecode=0:8309 \
    --change-name=0:disk-main-luks \
    "$DISK"
  partprobe "$DISK"
  udevadm settle
  sleep 2

  # Sanity check
  for label in disk-main-ESP disk-main-luks; do
    if [ ! -e "/dev/disk/by-partlabel/$label" ]; then
      gum log --level error "Expected /dev/disk/by-partlabel/$label after sgdisk."
      exit 1
    fi
  done

  # Clear stale signatures from both new partitions.
  for label in disk-main-ESP disk-main-luks; do
    PART=$(readlink -f "/dev/disk/by-partlabel/$label")
    blkdiscard -f "$PART" 2>/dev/null || true
    wipefs -af "$PART" 2>/dev/null || true
  done

  gum log --level info "New partitions ready; existing partitions untouched."
fi

cd "$STAGE"
git init -q
git add -A

gum log --level info "Locking installer flake inputs..."
nix --extra-experimental-features "nix-command flakes" flake lock

# Partition, format, mount (path depends on whether we wiped or carved)
if [ "$DISKO_MODE" = "disko" ]; then
  # Full-wipe path: disko handles everything (destroy + create + format + mount)
  gum log --level info "Running disko (destroy, format, mount)..."
  nix --extra-experimental-features "nix-command flakes" \
    run "github:nix-community/disko/latest" -- \
    --mode disko \
    --flake ".#installer"
else
  # Unalloc path: format ourselves, then use disko only to mount. Disko's
  # `--mode format` mishandles pre-existing partitions for vfat (produces a
  # boot sector with bogus reserved-sector count). Bypass it.
  ESP_PART=$(readlink -f /dev/disk/by-partlabel/disk-main-ESP)
  LUKS_PART=$(readlink -f /dev/disk/by-partlabel/disk-main-luks)

  gum log --level info "Formatting ESP ($ESP_PART) as FAT32..."
  mkfs.vfat -F 32 "$ESP_PART"

  gum log --level info "Formatting LUKS ($LUKS_PART)..."
  cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --pbkdf argon2id \
    --batch-mode \
    --key-file /tmp/install/luks.key \
    "$LUKS_PART"
  cryptsetup open --key-file /tmp/install/luks.key "$LUKS_PART" cryptroot

  gum log --level info "Creating ZFS pool zroot..."
  zpool create -f \
    -o ashift=12 \
    -O acltype=posixacl \
    -O atime=off \
    -O com.sun:auto-snapshot=false \
    -O compression=zstd \
    -O mountpoint=none \
    -O xattr=sa \
    zroot /dev/mapper/cryptroot

  gum log --level info "Creating ZFS datasets..."
  zfs create -o mountpoint=legacy zroot/root

  gum log --level info "Mounting filesystems via disko..."
  nix --extra-experimental-features "nix-command flakes" \
    run "github:nix-community/disko/latest" -- \
    --mode mount \
    --flake ".#installer"
fi

# Verify mounts exist before running nixos-install
gum log --level info "Verifying mounts under /mnt..."
mountpoint -q /mnt      || { gum log --level error "/mnt is not mounted";      exit 1; }
mountpoint -q /mnt/boot || { gum log --level error "/mnt/boot is not mounted"; exit 1; }
gum log --level info "Checks passed. /mnt and /mnt/boot are mounted."

# Stage the user password hash where activation will read it. Must exist
# before nixos-install runs since hashedPasswordFile is read during activation.
gum log --level info "Writing user password hash to /mnt/etc/users/taylor.hash..."
install -d -m 0755 /mnt/etc/users
printf '%s\n' "$USER_HASH" > /mnt/etc/users/taylor.hash
chmod 0600 /mnt/etc/users/taylor.hash
unset USER_HASH

# nixos-install
gum log --level info "Running nixos-install..."
nixos-install \
  --flake ".#installer" \
  --no-root-password \
  --root /mnt

# Per-host source-of-truth files live in /etc/nixos. postinstall.sh and the
# update alias sync these into the dotfiles repo before each rebuild.
install -d -m 0755 /mnt/etc/nixos
cp "$STAGE/disko.nix" /mnt/etc/nixos/disko.nix
cat > /mnt/etc/nixos/hostid.nix <<EOF
# Generated by install.sh; matches the hostId used when the ZFS pool was
# created. The pool will refuse to import on a system with a different hostId.
{ networking.hostId = "$HOSTID"; }
EOF

# Sentinel so postinstall.sh can confirm install.sh was used.
install -d -m 0755 /mnt/etc/nixos-installer
cp "$STAGE/configuration.nix" /mnt/etc/nixos-installer/configuration.nix

# Done
echo
gum style --border double --border-foreground 39 --padding "1 4" --bold "Install complete"
echo
gum log --level info "Reboot, log in as 'taylor' with the password you set, then run your postinstall."
if gum confirm "Reboot now?"; then
  umount -R /mnt 2>/dev/null || true
  reboot
fi