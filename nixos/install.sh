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
  | gum choose --header "Target disk (WILL BE WIPED):")
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

sed "s|@DISK@|$DISK|g" "$DISKO_TEMPLATE" > "$STAGE/disko.nix"
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

# Final confirmation
echo
gum style --foreground 196 --bold "DESTRUCTIVE OPERATION!"
gum log --level warn "Disk:     $DISK"
gum log --level warn "Hostname: $HOSTNAME"
gum log --level warn "HostId:   $HOSTID"
echo
gum confirm "Wipe $DISK and install?" \
  --affirmative "Yes, wipe and install" --negative "Abort" \
  || { gum log --level error "Aborted."; exit 1; }

# Wipe disk
gum log --level info "Wiping $DISK..."
umount -R /mnt 2>/dev/null || true
zpool labelclear -f "$DISK" 2>/dev/null || true

if ! blkdiscard -f "$DISK" 2>/dev/null; then
  gum log --level warn "blkdiscard unsupported, falling back to zero-write."
  # Cover at least the first 2 GiB, past the ESP and well past the LUKS header
  dd if=/dev/zero of="$DISK" bs=1M count=2048 conv=fsync status=progress
fi

wipefs -af "$DISK" || true
sgdisk --zap-all "$DISK" || true
partprobe "$DISK" || true
udevadm settle || true
sleep 2

# Verify drive wipe
gum log --level info "Post-wipe signatures (should be empty):"
if blkid "$DISK"* 2>/dev/null | tee /dev/stderr | grep -q .; then
  gum log --level error "Wipe failed, signatures still present. Aborting."
  exit 1
fi
gum log --level info "Disk is clean."

cd "$STAGE"
git init -q
git add -A

gum log --level info "Locking installer flake inputs..."
nix --extra-experimental-features "nix-command flakes" flake lock

# Partition, format, mount
gum log --level info "Running disko (destroy, format, mount)..."
nix --extra-experimental-features "nix-command flakes" \
  run "github:nix-community/disko/latest" -- \
  --mode disko \
  --flake ".#installer"

# Verify mounts exist before running nixos-install
gum log --level info "Verifying mounts under /mnt..."
mountpoint -q /mnt      || { gum log --level error "/mnt is not mounted";      exit 1; }
mountpoint -q /mnt/boot || { gum log --level error "/mnt/boot is not mounted"; exit 1; }
gum log --level info "Checks passed. /mnt and /mnt/boot are mounted."

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

# Keep the installer's minimal configuration.nix around so postinstall.sh can
# detect whether the default 'password' is still active.
install -d -m 0755 /mnt/etc/nixos-installer
cp "$STAGE/configuration.nix" /mnt/etc/nixos-installer/configuration.nix

# Done
echo
gum style --border double --border-foreground 39 --padding "1 4" --bold "Install complete"
echo
gum log --level info "Reboot, log in as 'taylor' (password: 'password'), set a real password, then run your postinstall."
if gum confirm "Reboot now?"; then
  umount -R /mnt 2>/dev/null || true
  reboot
fi