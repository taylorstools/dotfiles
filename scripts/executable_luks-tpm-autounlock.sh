#!/usr/bin/env bash
#
# Enable or disable TPM2 auto-unlock for this host's LUKS root.
#
# The LUKS header is the source of truth for whether the TPM can actually
# unlock the disk; /etc/nixos/luks-tpm-autounlock.nix only decides whether the
# initrd bothers to try. This script always changes both together, because
# once they disagree the config lies to you: a crypttab that asks for the TPM
# when no token exists still boots -- it just stalls, fails, and falls through
# to the passphrase prompt with the reason buried behind `quiet`.
#
# /etc/nixos is the source of truth for the file itself. The `update` alias
# and the autoupgrade service copy it over the dotfiles copy before every
# rebuild, so editing the repo copy by hand does not survive. Use this script.

set -euo pipefail

if ! { [ -f /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release; }; then
  echo "This script can only be run on NixOS." >&2
  exit 1
fi

# cryptsetup is not in the system profile; re-exec under nix-shell once.
if ! command -v cryptsetup >/dev/null 2>&1 && [[ -z "${LTA_NIX_SHELL:-}" ]]; then
  export LTA_NIX_SHELL=1
  exec nix-shell -p cryptsetup tpm2-tools --run "$(printf '%q ' "$0" "$@")"
fi

#region Arguments

HOSTNAME_ARG=""
ACTION=""
DEVICE=""
NOREBUILD=false
ASSUME_YES=false
KEEP_SLOT=false

usage() {
  cat >&2 <<'USAGE'
Usage: luks-tpm-autounlock.sh --hostname <host> [options]

  --enable            Enrol the TPM2 keyslot and turn auto-unlock on
  --disable           Wipe the TPM2 keyslot and turn auto-unlock off
  --status            Report header state vs config state, change nothing
  --device <path>     LUKS device (skips the interactive chooser)
  --keep-slot         With --disable, leave the TPM2 keyslot in the header
  --norebuild         Write config but do not nixos-rebuild
  --yes               Assume yes for confirmations (for unattended use)

With no action flag, prompts interactively.
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--hostname) HOSTNAME_ARG="$2"; shift 2 ;;
    --enable)      ACTION="enable";  shift ;;
    --disable)     ACTION="disable"; shift ;;
    --status)      ACTION="status";  shift ;;
    --device)      DEVICE="$2"; shift 2 ;;
    --keep-slot)   KEEP_SLOT=true; shift ;;
    --norebuild)   NOREBUILD=true; shift ;;
    --yes|-y)      ASSUME_YES=true; shift ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$HOSTNAME_ARG" ]] || usage

DOTFILES="$HOME/.dotfiles"
HOST_DIR="$DOTFILES/nixos/hosts/$HOSTNAME_ARG"
ETC_FILE="/etc/nixos/luks-tpm-autounlock.nix"
DOT_FILE="$HOST_DIR/luks-tpm-autounlock.nix"
BACKUP_DIR="$HOME/luks-header-backups"

#endregion

#region Helpers

confirm() {
  $ASSUME_YES && return 0
  gum confirm "$1"
}

# All keyslot numbers in the header.
all_slots() {
  sudo cryptsetup luksDump "$1" | awk '
    /^Keyslots:/ { s = 1; next }
    /^Tokens:/   { s = 0 }
    s && /^  [0-9]+: luks2/ { gsub(":", "", $1); print $1 }
  '
}

# Keyslot numbers claimed by a systemd-tpm2 token.
tpm_slots() {
  sudo cryptsetup luksDump "$1" | awk '
    /^Tokens:/  { s = 1; next }
    /^Digests:/ { s = 0 }
    s && /systemd-tpm2/ { hit = 1; next }
    s && hit && $1 == "Keyslot:" { print $2; hit = 0 }
  '
}

# Slots you can actually type a passphrase into.
passphrase_slot_count() {
  local dev="$1" total tpm
  total=$(all_slots "$dev" | wc -l)
  tpm=$(tpm_slots "$dev" | wc -l)
  echo $(( total - tpm ))
}

has_tpm_token() { [[ -n "$(tpm_slots "$1")" ]]; }

config_wants_tpm() {
  [[ -f "$ETC_FILE" ]] && grep -qE '^[^#]*tpm2-device=auto' "$ETC_FILE"
}

choose_device() {
  [[ -n "$DEVICE" ]] && { echo "$DEVICE"; return; }

  mapfile -t DEVICES < <(
    lsblk -o PATH,FSTYPE,SIZE | awk '$2 == "crypto_LUKS" { print $1 " (" $3 ")" }'
  )

  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    gum log --level error "No LUKS partitions found."
    exit 1
  fi

  # Exactly one candidate is the normal case; do not make it a question.
  if [[ ${#DEVICES[@]} -eq 1 ]]; then
    awk '{print $1}' <<<"${DEVICES[0]}"
    return
  fi

  local selected
  selected=$(printf "%s\n" "${DEVICES[@]}" | gum choose --header "Select a LUKS device:")
  [[ -n "$selected" ]] || { gum log --level error "No selection made."; exit 1; }
  awk '{print $1}' <<<"$selected"
}

backup_header() {
  local dev="$1" stamp out
  stamp=$(date +%Y%m%d-%H%M%S)
  out="$BACKUP_DIR/$(basename "$dev")-$stamp.img"
  mkdir -p "$BACKUP_DIR"
  sudo cryptsetup luksHeaderBackup "$dev" --header-backup-file "$out"
  sudo chown "$USER:" "$out"
  chmod 600 "$out"
  gum log --level info "Header backed up to $out"
  gum log --level warn "That file plus your passphrase decrypts the disk. Move it off this machine."
}

# Refuse to leave the disk with no way in but the TPM.
require_passphrase_slot() {
  local dev="$1" n
  n=$(passphrase_slot_count "$dev")
  if [[ "$n" -lt 1 ]]; then
    gum log --level error "$dev has no passphrase keyslot -- only the TPM can open it."
    gum log --level error "Enrol one with 'cryptsetup luksAddKey $dev' before continuing."
    exit 1
  fi
}

#endregion

#region Status

print_status() {
  local dev="$1" header config
  has_tpm_token "$dev" && header="enrolled" || header="not enrolled"
  config_wants_tpm    && config="tpm2-device=auto" || config="passphrase only"

  gum log --level info "Device:  $dev"
  gum log --level info "Header:  TPM2 keyslot $header"
  gum log --level info "Config:  $ETC_FILE -> $config"
  gum log --level info "Slots:   $(passphrase_slot_count "$dev") passphrase, $(tpm_slots "$dev" | wc -l) TPM"

  if [[ "$header" == "not enrolled" ]] && config_wants_tpm; then
    echo
    gum log --level warn "Drift: the initrd asks the TPM to unlock, but no TPM keyslot exists."
    gum log --level warn "Boot still works -- it stalls, fails, then prompts. Run --disable to settle it."
    return 1
  fi

  if [[ "$header" == "enrolled" ]] && ! config_wants_tpm; then
    echo
    gum log --level warn "Drift: a TPM keyslot can open this disk, but the initrd never asks it."
    gum log --level warn "Run --disable to wipe the slot, or --enable to use it."
    return 1
  fi

  return 0
}

#endregion

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "LUKS TPM Auto-Unlock"

DEVICE=$(choose_device)

if [[ "$ACTION" == "status" ]]; then
  print_status "$DEVICE" || exit 1
  echo
  gum log --level info "Header and config agree."
  exit 0
fi

if [[ -z "$ACTION" ]]; then
  print_status "$DEVICE" || true
  echo
  gum confirm "Enable LUKS auto-unlock with TPM?" && ACTION="enable" || ACTION="disable"
fi

#region Header changes

if [[ "$ACTION" == "enable" ]]; then
  require_passphrase_slot "$DEVICE"

  if has_tpm_token "$DEVICE"; then
    gum log --level info "A TPM2 keyslot already exists on $DEVICE."
    if confirm "Re-enrol it? (needed after a firmware update or Secure Boot change)"; then
      backup_header "$DEVICE"
      sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEVICE"
      sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 "$DEVICE"
    fi
  else
    backup_header "$DEVICE"
    gum log --level info "Enrolling TPM2 (PCR 0+7)..."
    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 "$DEVICE"
  fi

  if ! has_tpm_token "$DEVICE"; then
    gum log --level error "Enrolment reported success but no TPM2 token is present. Aborting."
    exit 1
  fi
  gum log --level info "TPM2 keyslot present on $DEVICE."

else
  if has_tpm_token "$DEVICE"; then
    if $KEEP_SLOT; then
      gum log --level warn "Leaving the TPM2 keyslot in place (--keep-slot)."
      gum log --level warn "The disk stays TPM-openable; only the initrd stops asking."
    else
      require_passphrase_slot "$DEVICE"
      gum log --level info "Wiping the TPM2 keyslot so the header matches the config..."
      backup_header "$DEVICE"
      sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEVICE"

      if has_tpm_token "$DEVICE"; then
        gum log --level error "TPM2 token still present after wipe. Aborting."
        exit 1
      fi
      gum log --level info "TPM2 keyslot removed."
    fi
  else
    gum log --level info "No TPM2 keyslot on $DEVICE; nothing to wipe."
  fi
fi

#endregion

#region Write config

GENERATED="# Generated by scripts/luks-tpm-autounlock.sh -- do not edit by hand.
# /etc/nixos is the source of truth; the update alias and autoupgrade service
# copy it over the dotfiles copy before every rebuild."

if [[ "$ACTION" == "enable" ]]; then
  sudo tee "$ETC_FILE" > /dev/null <<EOF
$GENERATED
#
# TPM2 auto-unlock is ON: a TPM2 keyslot is enrolled (PCR 0+7) and the initrd
# uses it. The passphrase prompt still appears whenever the PCRs no longer
# match -- firmware updates, Secure Boot changes, key re-enrolment.
{ ... }:

{
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];
}
EOF
  gum log --level info "Wrote $ETC_FILE (auto-unlock enabled)."
else
  sudo tee "$ETC_FILE" > /dev/null <<EOF
$GENERATED
#
# TPM2 auto-unlock is OFF: the LUKS passphrase is entered at every boot.
{ ... }:

{
  # Kept regardless of TPM state. The systemd initrd runs the password agent
  # that draws the Plymouth passphrase prompt; dropping it here would silently
  # send this host back to the scripted initrd.
  boot.initrd.systemd.enable = true;
}
EOF
  gum log --level info "Wrote $ETC_FILE (auto-unlock disabled)."
fi

#endregion

#region Sync and rebuild

if [ -d "$HOST_DIR" ]; then
  sudo cp -f "$ETC_FILE" "$DOT_FILE"
  sudo chown "$USER:" "$DOT_FILE"
  git -C "$DOTFILES" add -f "nixos/hosts/$HOSTNAME_ARG/luks-tpm-autounlock.nix"
  gum log --level info "Synced to $DOT_FILE."
else
  gum log --level warn "Host directory $HOST_DIR not found; skipping dotfiles sync."
fi

ACTION_UPPER=$([[ "$ACTION" == "enable" ]] && echo "ENABLED" || echo "DISABLED")

if $NOREBUILD; then
  echo
  gum log --level info "LUKS TPM auto-unlock $ACTION_UPPER."
  gum log --level info "Rebuild required before the change takes effect."
else
  echo
  gum log --level info "Rebuilding system configuration..."
  sudo nixos-rebuild switch --flake "$DOTFILES/nixos#$HOSTNAME_ARG"
  echo
  gum log --level info "LUKS TPM auto-unlock $ACTION_UPPER."
fi

#endregion
