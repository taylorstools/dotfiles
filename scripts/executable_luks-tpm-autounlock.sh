#!/usr/bin/env bash

set -euo pipefail

if ! { [ -f /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release; }; then
  gum log --level error "This script can only be run on NixOS."
  exit 1
fi

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
      gum log --level error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$HOSTNAME" ]]; then
  gum log --level error "Usage: $0 --hostname <hostname> [--enable|--disable]"
  exit 1
fi

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "LUKS TPM Auto-Unlock"

# ===== Prompt if --enable/--disable not provided =====

if [[ -z "$ENABLE" ]]; then
  gum confirm "Enable LUKS auto-unlock with TPM?" && ENABLE=true || ENABLE=false
else
  action=$($ENABLE && echo "Enabling" || echo "Disabling")
  gum log --level info "$action LUKS auto-unlock with TPM..."
fi

# ===== Enroll TPM into LUKS device =====

if [[ "$ENABLE" == true ]]; then
  echo ""
  DEVICE=$(
    nix-shell -p tpm2-tools gum --run '
      set -e

      mapfile -t DEVICES < <(lsblk -o PATH,FSTYPE,SIZE,MOUNTPOINT | awk '"'"'$2=="crypto_LUKS" {print $1 " (" $3 ")"}'"'"')

      if [[ ${#DEVICES[@]} -eq 0 ]]; then
        gum log --level error "No LUKS partitions found."
        exit 1
      fi

      SELECTED=$(printf "%s\n" "${DEVICES[@]}" | gum choose --header "Select a LUKS device:")

      if [[ -z "$SELECTED" ]]; then
        gum log --level error "No selection made."
        exit 1
      fi

      DEVICE=$(echo "$SELECTED" | awk "{print \$1}")

      echo "$DEVICE"

      gum log --level info "Enrolling TPM2..." >&2
      sudo systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0+7 \
        "$DEVICE" >&2
    '
  )

  gum log --level info "TPM enrolled to $DEVICE."

  # ===== Generate luks-tpm-autounlock.nix =====

  echo ""
  export DEVICE=$DEVICE

  UUID=$(
    nix-shell -p cryptsetup --run '
      set -e
      UUID=$(sudo cryptsetup luksUUID "$DEVICE")
      echo "$UUID"
    '
  )

  [ -z "$UUID" ] && { gum log --level error "Failed to determine UUID for $DEVICE."; exit 1; }

  NIX_FILE="$HOME/.dotfiles/nixos/hosts/$HOSTNAME/luks-tpm-autounlock.nix"

  [ -f "$NIX_FILE" ] && rm -f "$NIX_FILE"

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

  gum log --level info "Generated luks-tpm-autounlock.nix for $HOSTNAME."
fi

# ===== Edit configuration.nix import =====

echo ""
CONFIG="$HOME/.dotfiles/nixos/hosts/$HOSTNAME/configuration.nix"
TARGET="./luks-tpm-autounlock.nix"

[ ! -f "$CONFIG" ] && { gum log --level error "$CONFIG does not exist."; exit 1; }

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
gum log --level info "Edited configuration.nix for $HOSTNAME to $action luks-tpm-autounlock.nix."

# ===== Rebuild system =====

echo ""
gum log --level info "Rebuilding system configuration..."
sudo nixos-rebuild switch --flake "$HOME/.dotfiles/nixos#$HOSTNAME"

action=$($ENABLE && echo "ENABLED" || echo "DISABLED")
echo ""
gum log --level info "LUKS TPM auto-unlock $action."