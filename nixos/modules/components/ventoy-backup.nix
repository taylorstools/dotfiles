
# Before the first run, create the credentials file if it doesn't exist:
#   sudo install -m 0600 -o root -g root /dev/null /etc/ventoy-backup-smb.cred
#   sudo tee /etc/ventoy-backup-smb.cred >/dev/null <<'EOF'
#   username=taylor
#   password=YOUR_PASSWORD
#   EOF
#
# Dry run:
#   sudo ventoy-backup --dry-run

{ pkgs, ... }:

let
  ventoy-backup = pkgs.writeShellApplication {
    name = "ventoy-backup";
    runtimeInputs = with pkgs; [ util-linux rsync coreutils findutils cifs-utils bash ];
    text = ''
      # Config
      SrcUuid="4E21-0000"                       # PC Toolkit (exFAT) volume serial
      SmbShare="//192.168.0.63/taylornas"       # CIFS share root
      SmbSubdir="Ventoy Backup"                 # folder within the share
      CredFile="/etc/ventoy-backup-smb.cred"    # root:root 0600, NOT in git
      WorkDir="/run/ventoy-backup"
      SrcMnt="$WorkDir/src"
      DstMnt="$WorkDir/dst"

      # rsync options: mirror an exFAT source onto a CIFS target.
      # Drop perms/owner/group (meaningless across exFAT and CIFS) and widen the
      # mtime window so FAT-style timestamp rounding doesn't re-copy everything.
      # shellcheck disable=SC2016  # $RECYCLE.BIN must stay literal, not expand
      RsyncArgs=(
        -rt --modify-window=1
        --no-perms --no-owner --no-group
        --delete
        --exclude='System Volume Information'
        --exclude='$RECYCLE.BIN'
        --info=stats2
      )

      if [[ "''${1:-}" == "--dry-run" ]]; then
        RsyncArgs+=( -n )
        echo "DRY-RUN: no changes will be written to the NAS."
      fi

      # Resolve the USB source: reuse an existing mount if one exists, otherwise
      # mount it ourselves read-only by UUID.
      MountedSrc=""
      WeMountedSrc=0

      ExistingMnt="$(findmnt -nr -S "UUID=$SrcUuid" -o TARGET 2>/dev/null | head -n1 || true)"
      if [[ -n "$ExistingMnt" ]]; then
        echo "USB already mounted at: $ExistingMnt"
        MountedSrc="$ExistingMnt"
      else
        DevPath="/dev/disk/by-uuid/$SrcUuid"
        if [[ ! -e "$DevPath" ]]; then
          echo "USB (UUID=$SrcUuid) not present. Nothing to back up; exiting cleanly."
          exit 0
        fi
        mkdir -p "$SrcMnt"
        echo "Mounting USB read-only: $DevPath -> $SrcMnt"
        mount -t exfat -o ro "$DevPath" "$SrcMnt"
        MountedSrc="$SrcMnt"
        WeMountedSrc=1
      fi

      # Always tear down anything we mounted, even on error.
      cleanup() {
        if mountpoint -q "$DstMnt"; then
          umount "$DstMnt" || true
        fi
        if [[ "$WeMountedSrc" -eq 1 ]] && mountpoint -q "$SrcMnt"; then
          umount "$SrcMnt" || true
        fi
      }
      trap cleanup EXIT

      # Safety guard: an empty or unmounted source with --delete would wipe the
      # NAS copy. Refuse to proceed in that case.
      if ! mountpoint -q "$MountedSrc"; then
        echo "ERROR: source $MountedSrc is not a mountpoint. Aborting before any deletion." >&2
        exit 1
      fi
      if [[ -z "$(find "$MountedSrc" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
        echo "ERROR: source $MountedSrc is empty. Refusing --delete (would wipe the NAS copy)." >&2
        exit 1
      fi

      # Skip cleanly if the NAS isn't reachable (e.g. this machine is off the
      # home network) instead of hanging on the CIFS mount's connect timeout.
      ServerHost="''${SmbShare#//}"
      ServerHost="''${ServerHost%%/*}"
      if ! timeout 5 bash -c "echo > /dev/tcp/$ServerHost/445" 2>/dev/null; then
        echo "NAS $ServerHost:445 not reachable; skipping this run."
        exit 0
      fi

      # Mount the SMB destination.
      if [[ ! -f "$CredFile" ]]; then
        echo "ERROR: credentials file $CredFile is missing." >&2
        exit 1
      fi
      mkdir -p "$DstMnt"
      echo "Mounting SMB share: $SmbShare -> $DstMnt"
      mount -t cifs "$SmbShare" "$DstMnt" \
        -o "credentials=$CredFile,iocharset=utf8,nounix,file_mode=0644,dir_mode=0755"

      DstDir="$DstMnt/$SmbSubdir"
      mkdir -p "$DstDir"

      echo "Backup: $MountedSrc/  ->  $DstDir/"
      rsync "''${RsyncArgs[@]}" "$MountedSrc/" "$DstDir/"
      echo "Backup complete."
    '';
  };
in
{
  # Kernel support for the filesystems we mount at run time.
  boot.supportedFilesystems = [ "cifs" "exfat" ];

  # Make `sudo ventoy-backup --dry-run` available from a shell.
  environment.systemPackages = [ ventoy-backup ];

  systemd.services.ventoy-backup = {
    description = "Mirror Ventoy PC Toolkit partition to NAS";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ventoy-backup}/bin/ventoy-backup";
      TimeoutStartSec = "3h";
    };
  };

  systemd.timers.ventoy-backup = {
    description = "Hourly Ventoy PC Toolkit backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
