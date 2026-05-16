#!/usr/bin/env bash
set -euo pipefail
clear

if [ "$(id -u)" -ne 0 ]; then
  gum log --level error "Run as root (sudo -i, then ./install)."
  exit 1
fi

REPO="https://github.com/taylorstools/dotfiles"
WORK="/tmp/install"
DOTFILES="$WORK/dotfiles"

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "NixOS Install Script"

# ===== Clone dotfiles to get install templates =====
mkdir -p "$WORK"
if [ ! -d "$DOTFILES" ]; then
  gum log --level info "Cloning dotfiles..."
  git clone --depth 1 "$REPO" "$DOTFILES"
else
  gum log --level info "Dotfiles already present; pulling..."
  git -C "$DOTFILES" pull --ff-only
fi

TEMPLATE_DIR="$DOTFILES/nixos/install"
DISKO_TEMPLATE="$TEMPLATE_DIR/disko.nix"
CONFIG_TEMPLATE="$TEMPLATE_DIR/configuration.nix"
FLAKE_TEMPLATE="$TEMPLATE_DIR/flake.nix"

for f in "$DISKO_TEMPLATE" "$CONFIG_TEMPLATE" "$FLAKE_TEMPLATE"; do
  [ -f "$f" ] || { gum log --level error "Missing template: $f"; exit 1; }
done

# ===== Choose target disk =====
echo
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

# ===== Hostname + ZFS hostId =====
HOSTNAME=$(gum input --header "Hostname for the minimal install:" \
                    --value "nixos" --placeholder "nixos")
[ -z "$HOSTNAME" ] && { gum log --level error "Hostname required."; exit 1; }

HOSTID=$(head -c4 /dev/urandom | od -A none -tx4 | tr -d ' ')
gum log --level info "Generated networking.hostId = $HOSTID"

# ===== Brand the live ISO with the chosen hostId =====
# So the ZFS pool gets created with the same hostId we bake into the config.
gum log --level info "Setting /etc/hostid on live ISO to $HOSTID..."
rm -f /etc/hostid
if command -v zgenhostid >/dev/null; then
  zgenhostid -f "$HOSTID"
else
  printf '%b' "\x${HOSTID:6:2}\x${HOSTID:4:2}\x${HOSTID:2:2}\x${HOSTID:0:2}" \
    > /etc/hostid
fi

# Sanity check: `hostid` should now print $HOSTID
got=$(hostid)
[ "$got" = "$HOSTID" ] || gum log --level warn "hostid reports '$got', expected '$HOSTID' — proceeding anyway"

# ===== Stage configs with substitutions =====
STAGE="$WORK/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"

sed "s|@DISK@|$DISK|g" "$DISKO_TEMPLATE" > "$STAGE/disko.nix"
sed -e "s|@HOSTNAME@|$HOSTNAME|g" -e "s|@HOSTID@|$HOSTID|g" \
    "$CONFIG_TEMPLATE" > "$STAGE/configuration.nix"
cp "$FLAKE_TEMPLATE" "$STAGE/flake.nix"

# ===== Optional review =====
echo
if gum confirm "Review/edit disko.nix?"; then
  ${EDITOR:-nano} "$STAGE/disko.nix"
fi
if gum confirm "Review/edit configuration.nix?"; then
  ${EDITOR:-nano} "$STAGE/configuration.nix"
fi

# ===== Final confirmation =====
echo
gum style --foreground 196 --bold "===  DESTRUCTIVE OPERATION  ==="
gum log --level warn "Disk:     $DISK"
gum log --level warn "Hostname: $HOSTNAME"
gum log --level warn "HostId:   $HOSTID"
echo
gum confirm "Wipe $DISK and install?" \
  --affirmative "Yes, wipe and install" --negative "Abort" \
  || { gum log --level error "Aborted."; exit 1; }

# ===== Partition + install in one shot =====
cd "$STAGE"

# Make this a git-tracked flake so Nix is happy to lock it.
git init -q
git add -A

gum log --level info "Locking installer flake inputs..."
nix --extra-experimental-features "nix-command flakes" flake lock

gum log --level info "Running disko-install..."
nix --extra-experimental-features "nix-command flakes" \
  run "github:nix-community/disko#disko-install" -- \
  --flake ".#installer" \
  --write-efi-boot-entries \
  --disk main "$DISK"

# ===== Stash configs into the new system =====
install -d -m 0755 /mnt/etc/nixos-installer
cp "$STAGE"/{disko.nix,configuration.nix,flake.nix} /mnt/etc/nixos-installer/
# hostId is also baked into the installed config, but a tiny note for humans:
echo "$HOSTID" > /mnt/etc/nixos-installer/hostid

# ===== Done =====
echo
gum style --border double --border-foreground 39 --padding "1 4" --bold "Install complete"
gum log --level info "Reboot, log in as 'taylor' (password: changeme), set a real password, then run your postinstall."
if gum confirm "Reboot now?"; then
  umount -R /mnt 2>/dev/null || true
  reboot
fi