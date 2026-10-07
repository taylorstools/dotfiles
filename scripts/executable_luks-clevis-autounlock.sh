#!/usr/bin/env bash
#
# Set up, check or remove network-bound LUKS unlock for this host's root
# volume: a Clevis binding that needs both the Tang server and this machine's
# TPM to release the key, plus, on wifi-only hosts, the TPM-sealed wifi config
# the initrd joins the network with.
#
# The NixOS side (clevis-tang.nix, initrd-wifi.nix) is in the repo and builds
# on every install. What no rebuild can produce is the per-install state this
# script makes: the binding lives in the LUKS header, and the wifi credential
# is sealed against PCR 7, which every fresh install moves by generating new
# Secure Boot keys. So this runs after `sbctl enroll-keys` and a reboot, and
# refuses to run before.
#
# --enable is idempotent. On a host that is already set up it tests each piece
# by actually unlocking with it and only redoes what fails, which makes it the
# repair command too, after a BIOS update (PCR 0) or a Secure Boot change
# (PCR 7). --regen is the same action, under the name you would look for.
# A wifi credential that still decrypts but holds an old password (the
# network's password changed) is caught by comparing it with the password
# NetworkManager has saved; --reseal forces a fresh one regardless.
#
# The Tang URL and PCRs come from the host's NixOS config
# (myOptions.clevisTang.tangUrl / pcrIds), not from this file.

set -euo pipefail

if ! { [ -f /etc/os-release ] && grep -q '^ID=nixos' /etc/os-release; }; then
  echo "This script can only be run on NixOS." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "Don't run as root; sudo is invoked as needed." >&2
  exit 1
fi

# clevis and jq are not in the system profile; re-exec under nix-shell once.
if [[ -z "${LCA_NIX_SHELL:-}" ]] \
  && ! { command -v clevis && command -v jq \
         && command -v cryptsetup && command -v curl; } >/dev/null 2>&1; then
  export LCA_NIX_SHELL=1
  exec nix-shell -p clevis jq cryptsetup curl \
    --run "$(printf '%q ' "$0" "$@")"
fi

#region Arguments

HOSTNAME_ARG=""
ACTION=""
DEVICE=""
NOREBUILD=false
ASSUME_YES=false
RESEAL=false

usage() {
  cat >&2 <<'USAGE'
Usage: luks-clevis-autounlock.sh [options]

  --enable            Bind Clevis (Tang + TPM2) and, on wifi hosts, seal the
                      initrd wifi credential. On a host that is already set
                      up, redoes only what no longer unlocks.
  --regen             Same as --enable
  --reseal            --enable, and re-seal the wifi credential even if the
                      current one still decrypts (after a password change)
  --disable           Remove the Clevis binding from the LUKS header
  --status            Report state and test each piece; change nothing
  --hostname <host>   Defaults to this machine's hostname, and must match it
  --device <path>     LUKS device (skips the interactive chooser)
  --norebuild         Do not nixos-rebuild after sealing the credential
  --yes               Assume yes for confirmations, and trust the Tang
                      server's advertised keys without asking

With no action flag, reports status and offers to set up or repair.
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--hostname)   HOSTNAME_ARG="$2"; shift 2 ;;
    --enable|--regen) ACTION="enable"; shift ;;
    --reseal)        ACTION="enable"; RESEAL=true; shift ;;
    --disable)       ACTION="disable"; shift ;;
    --status)        ACTION="status"; shift ;;
    --device)        DEVICE="$2"; shift 2 ;;
    --norebuild)     NOREBUILD=true; shift ;;
    --yes|-y)        ASSUME_YES=true; shift ;;
    --help)          usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

# The binding and the credential are both tied to the TPM they are made on,
# so there is no such thing as running this for another host.
HOSTNAME_ARG="${HOSTNAME_ARG:-$(hostname)}"
if [[ "$HOSTNAME_ARG" != "$(hostname)" ]]; then
  echo "--hostname $HOSTNAME_ARG does not match this machine ($(hostname))." >&2
  echo "Run this on $HOSTNAME_ARG itself: what it makes is tied to that machine's TPM." >&2
  exit 1
fi

DOTFILES="$HOME/.dotfiles"
FLAKE="$DOTFILES/nixos"
HOST_DIR="$FLAKE/hosts/$HOSTNAME_ARG"
CRED_REL="nixos/hosts/$HOSTNAME_ARG/initrd-wifi.cred"
CRED_FILE="$DOTFILES/$CRED_REL"
CRED_NAME="wpa_supplicant.conf"   # must match LoadCredentialEncrypted= in initrd-wifi.nix
CRED_PCRS="7"                     # Secure Boot state only; see initrd-wifi.nix
TPM_ETC_FILE="/etc/nixos/luks-tpm-autounlock.nix"
BACKUP_DIR="$HOME/luks-header-backups"
NIX=(nix --extra-experimental-features "nix-command flakes")
CLEVIS=$(command -v clevis)

[[ -d "$HOST_DIR" ]] || { echo "Host directory not found: $HOST_DIR" >&2; exit 1; }

# The plaintext wifi config, for as long as it exists. Removed on any exit.
PLAINTEXT=""
cleanup() {
  if [[ -n "$PLAINTEXT" && -e "$PLAINTEXT" ]]; then
    shred -u "$PLAINTEXT" 2>/dev/null || rm -f "$PLAINTEXT"
  fi
}
trap cleanup EXIT

#endregion

#region Helpers

confirm() {
  $ASSUME_YES && return 0
  gum confirm "$1"
}

info()  { gum log --level info  "$@"; }
warn()  { gum log --level warn  "$@"; }
error() { gum log --level error "$@"; }

# One byte of an EFI global variable's payload (the first 4 bytes are its
# attributes), or nothing if the variable is absent.
efivar_byte() {
  local f="/sys/firmware/efi/efivars/$1-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  [[ -r "$f" ]] || return 0
  od -An -t u1 -j4 -N1 "$f" | tr -d ' '
}

# Enabled and out of Setup Mode, i.e. the keys PCR 7 will measure from now on
# are the ones in place.
secure_boot_ready() {
  [[ "$(efivar_byte SecureBoot)" == 1 && "$(efivar_byte SetupMode)" == 0 ]]
}

tang_reachable() {
  curl -sf --max-time 5 "$TANG_URL/adv" >/dev/null
}

config_wants_tpm() {
  [[ -f "$TPM_ETC_FILE" ]] && grep -qE '^[^#]*tpm2-device=auto' "$TPM_ETC_FILE"
}

choose_device() {
  [[ -n "$DEVICE" ]] && { echo "$DEVICE"; return; }

  # As root: the nix-shell this script re-execs into can put a udev-less
  # lsblk first on PATH, which has to probe the partitions itself to report
  # FSTYPE, and an unprivileged probe sees nothing.
  mapfile -t DEVICES < <(
    sudo lsblk -o PATH,FSTYPE,SIZE | awk '$2 == "crypto_LUKS" { print $1 " (" $3 ")" }'
  )

  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    error "No LUKS partitions found."
    exit 1
  fi

  # Exactly one candidate is the normal case; do not make it a question.
  if [[ ${#DEVICES[@]} -eq 1 ]]; then
    awk '{print $1}' <<<"${DEVICES[0]}"
    return
  fi

  local selected
  selected=$(printf "%s\n" "${DEVICES[@]}" | gum choose --header "Select a LUKS device:")
  [[ -n "$selected" ]] || { error "No selection made."; exit 1; }
  awk '{print $1}' <<<"$selected"
}

backup_header() {
  local dev="$1" stamp out
  stamp=$(date +%Y%m%d-%H%M%S)
  out="$BACKUP_DIR/$(basename "$(readlink -f "$dev")")-$stamp.img"
  mkdir -p "$BACKUP_DIR"
  sudo cryptsetup luksHeaderBackup "$dev" --header-backup-file "$out"
  sudo chown "$USER:" "$out"
  chmod 600 "$out"
  info "Header backed up to $out"
  warn "That file plus your passphrase decrypts the disk. Move it off this machine."
}

#endregion

#region Host config

# Everything the script needs to know about the host, read from its NixOS
# config so that the config stays the one place it is written down. Options a
# host does not import or does not set come back empty instead of failing.
read_config() {
  local json
  info "Reading $HOSTNAME_ARG's config from $FLAKE..."
  if ! json=$("${NIX[@]}" eval --json \
      "$FLAKE#nixosConfigurations.\"$HOSTNAME_ARG\".config.myOptions" \
      --apply '
        o: let
          try = v: d: let r = builtins.tryEval v; in if r.success then r.value else d;
        in {
          clevis = try (o.clevisTang.enable or false) false;
          tangUrl = try (o.clevisTang.tangUrl or "") "";
          pcrIds = try (o.clevisTang.pcrIds or "") "";
          wifiInterface = try (o.initrdWifi.interface or "") "";
          wifiFrequencies = try (o.initrdWifi.frequencies or [ ]) [ ];
        }'); then
    error "Could not evaluate nixosConfigurations.$HOSTNAME_ARG."
    exit 1
  fi

  CLEVIS_ENABLED=$(jq -r '.clevis' <<<"$json")
  TANG_URL=$(jq -r '.tangUrl' <<<"$json")
  PCR_IDS=$(jq -r '.pcrIds' <<<"$json")
  WIFI_IFACE=$(jq -r '.wifiInterface' <<<"$json")
  WIFI_FREQS=$(jq -r '.wifiFrequencies | map(tostring) | join(" ")' <<<"$json")
}

#endregion

#region LUKS header

# All keyslot numbers in the header.
all_slots() {
  sudo cryptsetup luksDump "$1" | awk '
    /^Keyslots:/ { s = 1; next }
    /^Tokens:/   { s = 0 }
    s && /^  [0-9]+: luks2/ { gsub(":", "", $1); print $1 }
  '
}

# "<token type> <keyslot>" for every token in the header.
token_slots() {
  sudo cryptsetup luksDump "$1" | awk '
    /^Tokens:/  { s = 1; next }
    /^Digests:/ { s = 0 }
    s && /^  [0-9]+: / { type = $2; next }
    s && $1 == "Keyslot:" { print type, $2 }
  '
}

tpm_slots()    { token_slots "$1" | awk '$1 == "systemd-tpm2" { print $2 }'; }
clevis_slots() { token_slots "$1" | awk '$1 == "clevis" { print $2 }'; }

# Slots you can actually type a passphrase into: everything no token claims.
passphrase_slot_count() {
  local dev="$1" total claimed
  total=$(all_slots "$dev" | wc -l)
  claimed=$(token_slots "$dev" | awk '{ print $2 }' | sort -u | wc -l)
  echo $(( total - claimed ))
}

# Refuse to touch a disk whose only way in would be Clevis or the TPM.
require_passphrase_slot() {
  local dev="$1" n
  n=$(passphrase_slot_count "$dev")
  if [[ "$n" -lt 1 ]]; then
    error "$dev has no passphrase keyslot."
    error "Enroll one with 'cryptsetup luksAddKey $dev' before continuing."
    exit 1
  fi
}

#endregion

#region Clevis

# Both pins, both required: Tang so the disk only opens on the home network,
# the TPM so it only opens inside this machine's signed boot.
policy_json() {
  jq -cn --arg url "$TANG_URL" --arg pcrs "$PCR_IDS" \
    '{t: 2, pins: {tang: [{url: $url}], tpm2: {pcr_bank: "sha256", pcr_ids: $pcrs}}}'
}

slot_list_line() { sudo "$CLEVIS" luks list -d "$1" -s "$2" 2>/dev/null; }

# A bound slot's pin config as JSON, e.g. {"t":2,"pins":{...}}.
slot_config() {
  slot_list_line "$1" "$2" | sed -n "s/^[0-9]*: [a-z0-9]* '\(.*\)'\$/\1/p"
}

# True when a slot is bound with exactly the policy the config asks for.
slot_matches() {
  local line cfg
  line=$(slot_list_line "$1" "$2")
  [[ "$(awk '{ print $2; exit }' <<<"$line")" == "sss" ]] || return 1
  cfg=$(slot_config "$1" "$2")
  jq -e --arg url "$TANG_URL" --arg pcrs "$PCR_IDS" '
    .t == 2
    and ([.. | objects | select(has("url"))     | .url]     == [$url])
    and ([.. | objects | select(has("pcr_ids")) | .pcr_ids] == [$pcrs])
  ' <<<"$cfg" >/dev/null 2>&1
}

# The real test: ask Tang and the TPM for the key, the way the initrd will.
# The key goes nowhere.
slot_unlocks() {
  sudo "$CLEVIS" luks pass -d "$1" -s "$2" >/dev/null 2>&1
}

slot_summary() {
  slot_config "$1" "$2" | jq -r '
    "tang " + ([.. | objects | select(has("url")) | .url] | join(","))
    + " + tpm2 pcrs " + ([.. | objects | select(has("pcr_ids")) | .pcr_ids] | join(","))
  ' 2>/dev/null || echo "unreadable"
}

#endregion

#region Wifi credential

cred_tracked() {
  git -C "$DOTFILES" ls-files --error-unmatch "$CRED_REL" >/dev/null 2>&1
}

cred_opens() {
  [[ -f "$CRED_FILE" ]] \
    && sudo systemd-creds decrypt --name="$CRED_NAME" "$CRED_FILE" - >/dev/null 2>&1
}

cred_ssid() {
  sudo systemd-creds decrypt --name="$CRED_NAME" "$CRED_FILE" - 2>/dev/null \
    | sed -n 's/^[[:space:]]*ssid="\(.*\)"$/\1/p' | head -n1
}

# The SSID NetworkManager is on right now. Terse mode backslash-escapes ':'
# and '\' in the name.
current_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null \
    | sed -n 's/^yes://p' | head -n1 | sed 's/\\\(.\)/\1/g'
}

# NetworkManager's connection on the wifi interface right now, if any.
nm_connection() {
  nmcli -g GENERAL.CONNECTION device show "$WIFI_IFACE" 2>/dev/null | head -n1
}

# The password NetworkManager has saved for a connection, or nothing. Tried
# as the user first (secrets held by an agent such as KWallet), then as root
# (secrets stored in the system connection file).
nm_password() {
  local conn="$1" pw=""
  pw=$(nmcli --escape no -s -g 802-11-wireless-security.psk connection show "$conn" 2>/dev/null) || pw=""
  if [[ -z "$pw" ]]; then
    pw=$(sudo nmcli --escape no -s -g 802-11-wireless-security.psk connection show "$conn" 2>/dev/null) || pw=""
  fi
  printf '%s' "$pw"
}

# The sealed config offers WPA2 and WPA3 (SAE, management frame protection
# optional) and lets the access point choose, which is what NetworkManager
# does for a "wpa-psk" connection. A 6 GHz radio only accepts WPA3, and a
# WPA2-only config can be turned away on the other bands too once the router
# prefers WPA3. SAE works from the passphrase itself rather than the PSK
# derived from it, so the config carries the passphrase.
WPA_KEY_MGMT="WPA-PSK WPA-PSK-SHA256 SAE"

# wpa_supplicant.conf quoted strings cannot hold a double quote or newline.
conf_safe() {
  [[ "$1" != *'"'* && "$1" != *$'\n'* ]]
}

# A passphrase both WPA2 (8-63 characters) and the config file can take.
passphrase_ok() {
  local n=${#1}
  (( n >= 8 && n <= 63 )) && conf_safe "$1"
}

write_wpa_config() {
  local ssid="$1" pass="$2" out="$3" freqs=""
  # freq_list in the network block limits which access points it will
  # connect to, not what it scans: the card only enables its 6 GHz channels
  # once a 2.4/5 GHz scan has told it the country, so a scan limited to
  # 6 GHz is refused outright. It comes from myOptions.initrdWifi.frequencies.
  if [[ -n "$WIFI_FREQS" ]]; then
    freqs=$'\tfreq_list='"$WIFI_FREQS"$'\n'
  fi
  # sae_pwe=2: hash-to-element as well as hunting-and-pecking; 6 GHz
  # requires hash-to-element.
  printf 'sae_pwe=2\n\nnetwork={\n\tssid="%s"\n\tkey_mgmt=%s\n\tieee80211w=1\n%s\tpsk="%s"\n\tsae_password="%s"\n}\n' \
    "$ssid" "$WPA_KEY_MGMT" "$freqs" "$pass" "$pass" > "$out"
}

cred_conf() {
  sudo systemd-creds decrypt --name="$CRED_NAME" "$CRED_FILE" - 2>/dev/null
}

# Sealed in the WPA2+WPA3 format above, not the older WPA2-only one.
cred_current_format() {
  cred_conf | grep -q "^[[:space:]]*key_mgmt=$WPA_KEY_MGMT\$"
}

# The credential allows exactly the frequencies the host config asks for.
cred_freqs_match() {
  local have
  have=$(cred_conf | sed -n 's/^[[:space:]]*freq_list=\(.*\)$/\1/p' | head -n1)
  [[ "$have" == "$WIFI_FREQS" ]]
}

cred_password() {
  cred_conf | sed -n 's/^[[:space:]]*sae_password="\(.*\)"$/\1/p' | head -n1
}

# Whether the sealed passphrase is the one NetworkManager connects with right
# now. 0: same. 1: different, so the network's password has changed since it
# was sealed. 2: cannot tell (not on that SSID, no saved password readable,
# or a credential in the older format).
cred_matches_nm() {
  local ssid conn pw have
  ssid=$(cred_ssid)
  [[ -n "$ssid" && "$(current_ssid)" == "$ssid" ]] || return 2
  conn=$(nm_connection)
  [[ -n "$conn" ]] || return 2
  pw=$(nm_password "$conn")
  [[ -n "$pw" ]] || return 2
  have=$(cred_password)
  [[ -n "$have" ]] || return 2
  [[ "$have" == "$pw" ]] || return 1
}

seal_credential() {
  local ssid pass="" conn
  ssid=$(current_ssid)
  if [[ -z "$ssid" ]]; then
    error "Not connected to wifi."
    error "Connect to the network $HOSTNAME_ARG should join at boot, then rerun."
    exit 1
  fi

  info "Sealing the initrd wifi config for SSID '$ssid' (WPA2 + WPA3; TPM, PCR $CRED_PCRS)."
  confirm "Is '$ssid' the network to join at boot?" || exit 1

  # Prefer the password NetworkManager is connected with right now: it is
  # known to work, and nothing has to be typed.
  conn=$(nm_connection)
  if [[ -n "$conn" ]]; then
    pass=$(nm_password "$conn")
  fi
  if [[ -n "$pass" ]] && passphrase_ok "$pass" \
     && confirm "Use the password NetworkManager has saved for '$ssid'?"; then
    info "Using NetworkManager's saved password."
  else
    pass=$(gum input --password --header "Passphrase for '$ssid':")
  fi

  if ! conf_safe "$ssid"; then
    unset pass
    error "The SSID contains a double quote, which this script cannot write into wpa_supplicant.conf."
    exit 1
  fi
  if ! passphrase_ok "$pass"; then
    unset pass
    error "The passphrase must be 8-63 characters, without a double quote."
    exit 1
  fi

  PLAINTEXT=$(umask 077; mktemp -p /dev/shm initrd-wifi.XXXXXX)
  write_wpa_config "$ssid" "$pass" "$PLAINTEXT"
  unset pass

  sudo systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs="$CRED_PCRS" \
    --name="$CRED_NAME" "$PLAINTEXT" "$CRED_FILE"
  cleanup
  PLAINTEXT=""
  sudo chown "$USER:" "$CRED_FILE"

  if ! cred_opens; then
    error "Sealed $CRED_FILE, but it does not decrypt. Not using it."
    exit 1
  fi
  info "Sealed $CRED_FILE."
}

#endregion

#region Status

print_status() {
  local dev="$1" problems=0 s tpm good=false match
  local -a slots

  if secure_boot_ready; then
    info "Secure Boot: enabled, keys enrolled"
  else
    warn "Secure Boot: off, or still in Setup Mode"
    problems=$(( problems + 1 ))
  fi

  if [[ "$CLEVIS_ENABLED" == true ]]; then
    info "Config:      clevis on; Tang $TANG_URL, TPM PCRs $PCR_IDS"
  else
    warn "Config:      myOptions.clevisTang.enable is off for $HOSTNAME_ARG"
    problems=$(( problems + 1 ))
  fi

  info "Device:      $dev ($(passphrase_slot_count "$dev") passphrase slot(s))"

  tpm=$(tpm_slots "$dev" | paste -sd, -)
  if [[ -n "$tpm" ]]; then
    warn "Drift:       systemd-tpm2 keyslot $tpm opens this disk before Clevis is asked, bypassing Tang."
    problems=$(( problems + 1 ))
  fi
  if config_wants_tpm; then
    warn "Drift:       $TPM_ETC_FILE still asks the TPM to unlock."
    problems=$(( problems + 1 ))
  fi

  mapfile -t slots < <(clevis_slots "$dev")
  if [[ ${#slots[@]} -eq 0 ]]; then
    warn "Clevis:      no binding in the header"
    problems=$(( problems + 1 ))
  fi
  for s in "${slots[@]}"; do
    if ! slot_matches "$dev" "$s"; then
      warn "Clevis:      slot $s ($(slot_summary "$dev" "$s")) does not match the config"
      problems=$(( problems + 1 ))
    elif slot_unlocks "$dev" "$s"; then
      info "Clevis:      slot $s matches the config and unlocks"
      good=true
    else
      warn "Clevis:      slot $s matches the config but does not unlock (PCRs moved, Tang down, or Tang keys rotated)"
      problems=$(( problems + 1 ))
    fi
  done
  if [[ ${#slots[@]} -gt 0 ]] && ! $good; then
    warn "Clevis:      nothing in the header unlocks right now"
  fi

  if [[ -n "$WIFI_IFACE" ]]; then
    if [[ ! -f "$CRED_FILE" ]]; then
      warn "Wifi:        $CRED_REL is not sealed yet; the initrd has no network"
      problems=$(( problems + 1 ))
    elif ! cred_tracked; then
      warn "Wifi:        $CRED_REL is not tracked by git, so the flake cannot see it"
      problems=$(( problems + 1 ))
    elif cred_opens; then
      info "Wifi:        credential opens; SSID '$(cred_ssid)' on $WIFI_IFACE"
      match=0
      if ! cred_current_format; then
        warn "Wifi:        sealed in the older WPA2-only format, which WPA3 and 6 GHz access points turn away. Run --enable."
        problems=$(( problems + 1 ))
        match=3
      else
        if ! cred_freqs_match; then
          warn "Wifi:        its allowed frequencies differ from myOptions.initrdWifi.frequencies. Run --enable."
          problems=$(( problems + 1 ))
        elif [[ -n "$WIFI_FREQS" ]]; then
          info "Wifi:        connects only on the frequencies in myOptions.initrdWifi.frequencies"
        fi
        cred_matches_nm || match=$?
      fi
      case "$match" in
        3) ;;
        0) info "Wifi:        its key matches the password NetworkManager connects with" ;;
        1) warn "Wifi:        its key does NOT match NetworkManager's saved password; the network's password has changed. Run --enable."
           problems=$(( problems + 1 )) ;;
        *) info "Wifi:        could not compare its key with NetworkManager's (not on that SSID, or no readable saved password)" ;;
      esac
    else
      warn "Wifi:        credential no longer opens (PCR 7 moved?)"
      problems=$(( problems + 1 ))
    fi
  fi

  [[ "$problems" -eq 0 ]]
}

#endregion

#region Enable

do_enable() {
  local dev="$1" s good="" changed=false match
  local -a slots stale=() bind_args=() quiet_args=()
  $ASSUME_YES && quiet_args=(-q)

  if ! secure_boot_ready; then
    error "Secure Boot is off, or the firmware is still in Setup Mode."
    error "Enroll keys (sudo sbctl enroll-keys --microsoft) and reboot first."
    error "Anything bound before that is bound to a PCR 7 that is about to change."
    exit 1
  fi
  if [[ "$CLEVIS_ENABLED" != true ]]; then
    error "myOptions.clevisTang.enable is not set for $HOSTNAME_ARG."
    error "Import clevis-tang.nix and enable it in hosts/$HOSTNAME_ARG/configuration.nix first."
    exit 1
  fi
  if config_wants_tpm; then
    error "$TPM_ETC_FILE still asks the TPM to unlock."
    error "Run luks-tpm-autounlock.sh --hostname $HOSTNAME_ARG --disable first; it settles the keyslot and that file together."
    exit 1
  fi
  if ! tang_reachable; then
    error "Tang at $TANG_URL is not answering. Binding and repair both need it."
    exit 1
  fi

  require_passphrase_slot "$dev"

  #region TPM keyslot
  # systemd-cryptsetup tries enrolled tokens before it asks for a password,
  # so a leftover TPM keyslot opens the disk on its own and Tang is never
  # consulted, whatever crypttab says.
  if [[ -n "$(tpm_slots "$dev")" ]]; then
    warn "A systemd-tpm2 keyslot is enrolled. It opens the disk before Clevis is asked, bypassing Tang."
    confirm "Wipe the TPM2 keyslot?" || { error "Leaving it in place defeats the point. Aborting."; exit 1; }
    backup_header "$dev"
    sudo systemd-cryptenroll --wipe-slot=tpm2 "$dev"
    if [[ -n "$(tpm_slots "$dev")" ]]; then
      error "TPM2 token still present after wipe. Aborting."
      exit 1
    fi
    info "TPM2 keyslot removed."
  fi
  #endregion

  #region Wifi credential
  if [[ -n "$WIFI_IFACE" ]]; then
    match=2
    if cred_opens; then
      cred_matches_nm || match=$?
    fi

    if $RESEAL; then
      info "Re-sealing the wifi credential (--reseal)."
      seal_credential
      changed=true
    elif ! cred_opens; then
      if [[ -f "$CRED_FILE" ]]; then
        warn "Wifi credential no longer opens; re-sealing."
      fi
      seal_credential
      changed=true
    elif ! cred_current_format; then
      warn "Wifi credential is in the older WPA2-only format; re-sealing for WPA2 and WPA3."
      seal_credential
      changed=true
    elif ! cred_freqs_match; then
      warn "Wifi credential allows different frequencies than myOptions.initrdWifi.frequencies; re-sealing."
      seal_credential
      changed=true
    elif [[ "$match" -eq 1 ]]; then
      warn "Wifi credential opens, but its key is not the password NetworkManager connects to '$(cred_ssid)' with."
      warn "The network's password has changed since it was sealed; re-sealing."
      seal_credential
      changed=true
    else
      info "Wifi credential still opens (SSID '$(cred_ssid)'); keeping it."
      if [[ "$match" -ne 0 ]]; then
        warn "Could not compare its key with NetworkManager's saved password. If the network's password changed, rerun with --reseal."
      fi
    fi
    if ! cred_tracked || ! git -C "$DOTFILES" diff --quiet -- "$CRED_REL"; then
      git -C "$DOTFILES" add -f "$CRED_REL"
      info "Staged $CRED_REL."
      changed=true
    fi
  fi
  #endregion

  #region Clevis binding
  mapfile -t slots < <(clevis_slots "$dev")
  for s in "${slots[@]}"; do
    if ! slot_matches "$dev" "$s" || [[ -n "$good" ]]; then
      stale+=("$s")
      continue
    fi
    if slot_unlocks "$dev" "$s"; then
      info "Clevis slot $s matches the config and unlocks."
      good="$s"
      continue
    fi

    warn "Clevis slot $s matches the config but no longer unlocks (PCRs moved, or Tang rotated its keys). Regenerating..."
    backup_header "$dev"
    sudo "$CLEVIS" luks regen "${quiet_args[@]}" -d "$dev" -s "$s"
    if ! slot_unlocks "$dev" "$s"; then
      error "Slot $s still does not unlock after regenerating."
      exit 1
    fi
    info "Clevis slot $s regenerated; it unlocks."
    good="$s"
  done

  if [[ -z "$good" ]]; then
    info "Binding Clevis: Tang $TANG_URL + TPM2 PCRs $PCR_IDS. Enter the existing LUKS passphrase when asked."
    bind_args=(-d "$dev")
    $ASSUME_YES && bind_args=(-y "${bind_args[@]}")
    sudo "$CLEVIS" luks bind "${bind_args[@]}" sss "$(policy_json)"

    for s in $(clevis_slots "$dev"); do
      if [[ " ${stale[*]} " != *" $s "* ]] && slot_matches "$dev" "$s" && slot_unlocks "$dev" "$s"; then
        good="$s"
        break
      fi
    done
    if [[ -z "$good" ]]; then
      error "Bound, but no matching slot unlocks. Check: sudo clevis luks list -d $dev"
      exit 1
    fi
    info "Bound slot $good; it unlocks."
  fi

  # Bindings made for another Tang URL or PCR set, or duplicates. Only
  # offered once a matching one has proven it works.
  if [[ ${#stale[@]} -gt 0 ]]; then
    warn "Slot(s) ${stale[*]} are Clevis bindings other than slot $good (old Tang URL or PCRs, or duplicates)."
    if confirm "Remove them? Slot $good stays."; then
      backup_header "$dev"
      for s in "${stale[@]}"; do
        if $ASSUME_YES; then
          sudo "$CLEVIS" luks unbind -f -d "$dev" -s "$s"
        else
          sudo "$CLEVIS" luks unbind -d "$dev" -s "$s"
        fi
      done
    fi
  fi
  #endregion

  #region Rebuild
  echo
  if ! $changed; then
    info "Nothing the build reads changed; no rebuild needed."
  elif $NOREBUILD; then
    info "Rebuild required before the new credential reaches the initrd."
  else
    info "Rebuilding system configuration..."
    sudo nixos-rebuild switch --flake "$FLAKE#$HOSTNAME_ARG"
  fi
  #endregion

  echo
  info "Clevis unlock ENABLED on $dev (slot $good)."
  info "Reboot without touching the keyboard; it should come up on its own. Then:"
  info "  journalctl -b -u systemd-cryptsetup@cryptroot -u initrd-wpa-supplicant -u clevis-luks-askpass"
  if [[ -n "$WIFI_IFACE" ]] && $changed; then
    warn "Commit and push $CRED_REL: every checkout that builds $HOSTNAME_ARG needs the current one."
  fi
}

#endregion

#region Disable

do_disable() {
  local dev="$1" s
  local -a slots

  mapfile -t slots < <(clevis_slots "$dev")
  if [[ ${#slots[@]} -eq 0 ]]; then
    info "No Clevis binding on $dev; nothing to remove."
    return
  fi

  require_passphrase_slot "$dev"
  warn "Removing Clevis slot(s) ${slots[*]}. $dev will ask for the passphrase at every boot."
  confirm "Remove the Clevis binding?" || exit 1

  backup_header "$dev"
  for s in "${slots[@]}"; do
    if $ASSUME_YES; then
      sudo "$CLEVIS" luks unbind -f -d "$dev" -s "$s"
    else
      sudo "$CLEVIS" luks unbind -d "$dev" -s "$s"
    fi
  done

  if [[ -n "$(clevis_slots "$dev")" ]]; then
    error "A Clevis binding is still present. Check: sudo clevis luks list -d $dev"
    exit 1
  fi

  echo
  info "Clevis unlock DISABLED on $dev."
  if [[ "$CLEVIS_ENABLED" == true ]]; then
    warn "myOptions.clevisTang is still on for $HOSTNAME_ARG, so the initrd still waits for Clevis before showing the prompt."
    warn "Remove it from hosts/$HOSTNAME_ARG/configuration.nix to drop that wait."
  fi
}

#endregion

#region Main

gum style \
  --border double --border-foreground 39 \
  --padding "1 4" --margin "1 0" \
  --bold "LUKS Clevis Auto-Unlock"

read_config
DEVICE=$(choose_device)

case "$ACTION" in
  status)
    if print_status "$DEVICE"; then
      echo
      info "Everything checks out."
    else
      exit 1
    fi
    ;;
  enable)
    do_enable "$DEVICE"
    ;;
  disable)
    do_disable "$DEVICE"
    ;;
  "")
    if print_status "$DEVICE"; then
      echo
      info "Everything checks out; nothing to do."
      exit 0
    fi
    echo
    if gum confirm "Set up or repair Clevis unlock?"; then
      do_enable "$DEVICE"
    fi
    ;;
esac

#endregion
