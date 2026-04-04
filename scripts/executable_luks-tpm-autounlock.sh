#!/usr/bin/env bash

set -euo pipefail

if ! { [ -f /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release; }; then
  echo "Error: This script can only be run on NixOS."
  exit 1
fi

GREEN=$'\e[32m'
RESET=$'\e[0m'

HOSTNAME=""
ENABLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --enable)
      ENABLE=true
      shift
      ;;
    --disable)
      ENABLE=false
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$HOSTNAME" ]]; then
  echo "Usage: $0 --hostname <hostname> [--enable|--disable]"
  exit 1
fi

# Prompt user only if flag not provided
if [[ -z "$ENABLE" ]]; then
  read -rp "Enable LUKS auto-unlock with TPM? [Y/n]: " RESP
  RESP=${RESP:-Y}
  if [[ "$RESP" =~ ^[Yy]$ ]]; then
    ENABLE=true
  else
    ENABLE=false
  fi
else
  action=$($ENABLE && echo "Enabling" || echo "Disabling")
  echo -e "${GREEN}$action LUKS auto-unlock with TPM...${RESET}"
fi

if [[ "$ENABLE" == true ]]; then
  # =======================================
  # ===== ENROLL TPM INTO LUKS DEVICE =====
  # =======================================

  echo
  DEVICE=$(
    nix-shell -p tpm2-tools gum --run '
      set -e

      mapfile -t DEVICES < <(lsblk -o PATH,FSTYPE,SIZE,MOUNTPOINT | awk '"'"'$2=="crypto_LUKS" {print $1 " (" $3 ")"}'"'"')

      if [[ ${#DEVICES[@]} -eq 0 ]]; then
        echo "No LUKS partitions found." >&2
        exit 1
      fi

      SELECTED=$(printf "%s\n" "${DEVICES[@]}" | gum choose --header "Select a LUKS device:")

      if [[ -z "$SELECTED" ]]; then
        echo "No selection made." >&2
        exit 1
      fi

      DEVICE=$(echo "$SELECTED" | awk "{print \$1}")

      # Print drive
      echo "$DEVICE"

      echo "Enrolling TPM2..." >&2
      sudo systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0+7 \
        "$DEVICE" >&2
    '
  )

  echo "TPM enrolled to $DEVICE."

  echo
  # ========================================================
  # ===== CREATE HOST-SPECIFIC luks-tpm-autounlock.nix =====
  # ========================================================

  export DEVICE=$DEVICE

  UUID=$(
    nix-shell -p cryptsetup --run '
      set -e
      UUID=$(sudo cryptsetup luksUUID "$DEVICE")
      echo "$UUID"
    '
  )

  [ -z "$UUID" ] && (echo "Failed to determine UUID for $DEVICE."; exit 1)

  NIX_FILE="$HOME/.dotfiles/nixos/hosts/$HOSTNAME/luks-tpm-autounlock.nix"

  # Remove existing
  [ -f "$NIX_FILE" ] && rm -f "$NIX_FILE"

  # Create file with substituted values
  cat > "$NIX_FILE" <<-EOF
	{ config, pkgs, ... }:

	{
	  boot.initrd.systemd.enable = true;

	  boot.initrd.luks.devices."luks-$UUID" = {
	    device = "/dev/disk/by-uuid/$UUID";
	    crypttabExtraOpts = [ "tpm2-device=auto" ];
	  };
	}
	EOF

  echo "Generated luks-tpm-autounlock.nix for $HOSTNAME."
fi

echo
# ====================================================================
# ===== EDIT CONFIGURATION.NIX TO IMPORT luks-tpm-autounlock.nix =====
# ====================================================================

CONFIG="$HOME/.dotfiles/nixos/hosts/$HOSTNAME/configuration.nix"
TARGET="./luks-tpm-autounlock.nix"

[ ! -f "$CONFIG" ] && (echo "Error: $CONFIG does not exist."; exit 1)

# Create temp configuration.nix
tmp="$(mktemp)"

awk -v target="$TARGET" -v enable="$ENABLE" '
{
  if ($0 ~ target) {
    match($0, /^[[:space:]]*/)
    indent = substr($0, RSTART, RLENGTH)

    line = $0
    sub(/^[[:space:]]*/, "", line)
    sub(/^#+/, "", line)
    sub(/^[[:space:]]*/, "", line)

    if (enable == "true") {
      print indent line
    } else {
      print indent "#" line
    }
  } else {
    print $0
  }
}
' "$CONFIG" > "$tmp"

mv "$tmp" "$CONFIG"

action=$($ENABLE && echo "include" || echo "exclude")
echo "Edited configuration.nix for $HOSTNAME to $action luks-tpm-autounlock.nix."

echo
# ==========================
# ===== REBUILD SYSTEM =====
# ==========================

echo -e "${GREEN}Rebuilding system configuration...${RESET}"
sudo nixos-rebuild switch --flake "$HOME/.dotfiles/nixos#$HOSTNAME"

action=$($ENABLE && echo "ENABLED" || echo "DISABLED")
echo
echo -e "${GREEN}LUKS TPM auto-unlock $action.${RESET}"