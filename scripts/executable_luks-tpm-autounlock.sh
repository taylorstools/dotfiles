#!/usr/bin/env bash

set -euo pipefail

if ! { [ -f /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release; }; then
  gum log --level error "This script can only be run on NixOS."
  exit 1
fi

HOSTNAME=""
ENABLE=""
NOREBUILD=false

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
    --norebuild)
      NOREBUILD=true
      shift
      ;;
    *)
      gum log --level error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$HOSTNAME" ]]; then
  gum log --level error "Usage: $0 --hostname <hostname> [--enable|--disable] [--norebuild]"
  exit 1
fi

DOTFILES="$HOME/.dotfiles"
HOST_DIR="$DOTFILES/nixos/hosts/$HOSTNAME"
ETC_FILE="/etc/nixos/luks-tpm-autounlock.nix"
DOT_FILE="$HOST_DIR/luks-tpm-autounlock.nix"

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "LUKS TPM Auto-Unlock"

# Prompt if --enable/--disable not provided
if [[ -z "$ENABLE" ]]; then
  gum confirm "Enable LUKS auto-unlock with TPM?" && ENABLE=true || ENABLE=false
else
  action=$($ENABLE && echo "Enabling" || echo "Disabling")
  gum log --level info "$action LUKS auto-unlock with TPM..."
fi

# Enroll TPM into a LUKS device (only when enabling)
if [[ "$ENABLE" == true ]]; then
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
fi

# Write /etc/nixos/luks-tpm-autounlock.nix (source of truth)
if [[ "$ENABLE" == true ]]; then
  sudo tee "$ETC_FILE" > /dev/null <<EOF
{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];
}
EOF
  gum log --level info "Wrote $ETC_FILE (TPM auto-unlock enabled)."
else
  # Empty module so the host's configuration.nix can keep its unconditional
  # `./luks-tpm-autounlock.nix` import without depending on whether TPM is on.
  sudo tee "$ETC_FILE" > /dev/null <<EOF
# TPM auto-unlock is disabled. This empty module keeps the host's
# configuration.nix import valid.
{ }
EOF
  gum log --level info "Wrote $ETC_FILE (disabled placeholder)."
fi

# Sync /etc/nixos -> dotfiles so the next rebuild picks it up
if [ -d "$HOST_DIR" ]; then
  sudo cp -f "$ETC_FILE" "$DOT_FILE"
  sudo chown "$USER:" "$DOT_FILE"
  git -C "$DOTFILES" add -f "nixos/hosts/$HOSTNAME/luks-tpm-autounlock.nix"
  gum log --level info "Synced to $DOT_FILE."
else
  gum log --level warn "Host directory $HOST_DIR not found; skipping dotfiles sync."
fi

# Rebuild system
if [[ "$NOREBUILD" == true ]]; then
  echo
  action=$($ENABLE && echo "ENABLED" || echo "DISABLED")
  gum log --level info "LUKS TPM auto-unlock $action."
  gum log --level info "Configuration rebuild required before changes go into effect."
else
  echo
  gum log --level info "Rebuilding system configuration..."
  sudo nixos-rebuild switch --flake "$DOTFILES/nixos#$HOSTNAME"
  action=$($ENABLE && echo "ENABLED" || echo "DISABLED")
  echo
  gum log --level info "LUKS TPM auto-unlock $action."
fi