#!/usr/bin/env bash

set -euo pipefail

HOSTNAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$HOSTNAME" ]]; then
  echo "Usage: $0 --hostname <hostname>"
  exit 1
fi

# Prompt user
read -rp "Enable LUKS auto-unlock with TPM2? (Y/n): " RESP
RESP=${RESP:-Y}
echo

ENABLE=false
if [[ "$RESP" =~ ^[Yy]$ ]]; then
  ENABLE=true
fi

# ============================================
# ===== ENROLL TPM INTO INTO LUKS DEVICE =====
# ============================================

if [[ "$ENABLE" == true ]]; then
  nix-shell -p tpm2-tools gum --run '
    set -e

    # Build list of LUKS devices
    mapfile -t DEVICES < <(lsblk -o PATH,FSTYPE,SIZE,MOUNTPOINT | awk '"'"'$2=="crypto_LUKS" {print $1 " (" $3 ")"}'"'"')

    if [[ ${#DEVICES[@]} -eq 0 ]]; then
      echo "No LUKS partitions found."
      exit 1
    fi

    # Let user choose
    SELECTED=$(printf "%s\n" "${DEVICES[@]}" | gum choose --header "Select a LUKS device:")

    if [[ -z "$SELECTED" ]]; then
      echo "No selection made."
      exit 1
    fi

    DEVICE=$(echo "$SELECTED" | awk "{print \$1}")

    echo "Selected: $DEVICE"
    echo
    echo "Enrolling TPM2 into LUKS device..."

    sudo systemd-cryptenroll \
      --tpm2-device=auto \
      --tpm2-pcrs=0+7 \
      "$DEVICE"
  '
fi

# ====================================================================
# ===== EDIT CONFIGURATION.NIX TO IMPORT luks-tpm-autounlock.nix =====
# ====================================================================

CONFIG="$HOME/.dotfiles/nixos/hosts/$HOSTNAME/configuration.nix"
TARGET='../../modules/luks-tpm-autounlock.nix'

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: $CONFIG does not exist"
  exit 1
fi

# Edit configuration.nix
tmp="$(mktemp)"

awk -v target="$TARGET" -v enable="$ENABLE" -f <(cat <<'EOF'
{
  if ($0 ~ target) {
    # Capture leading whitespace
    match($0, /^[[:space:]]*/)
    indent = substr($0, RSTART, RLENGTH)

    line = $0
    sub(/^[[:space:]]*/, "", line)
    sub(/^#+/, "", line)
    sub(/^[[:space:]]*/, "", line)

    if (enable == "true") {
      # Uncomment
      print indent line
    } else {
      # Comment out
      print indent "#" line
    }
  } else {
    print $0
  }
}
EOF
) "$CONFIG" > "$tmp"

mv "$tmp" "$CONFIG"

echo "$CONFIG updated."
if $ENABLE; then
  echo "TPM auto-unlock ENABLED."
else
  echo "TPM auto-unlock DISABLED."
fi

# ====================================================================
# ===== EDIT CONFIGURATION.NIX TO IMPORT luks-tpm-autounlock.nix =====
# ====================================================================