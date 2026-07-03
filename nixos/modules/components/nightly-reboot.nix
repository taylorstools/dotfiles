{ config, pkgs, lib, ... }:

let
  targetUser = "taylor";

  envBin = "${pkgs.coreutils}/bin/env";
  kdotoolBin = "${pkgs.kdotool}/bin/kdotool";

  rebootIfIdle = pkgs.writeShellApplication {
    name = "nightly-reboot";
    runtimeInputs = [ pkgs.util-linux pkgs.systemd pkgs.coreutils pkgs.kdotool ];
    text = ''
      UserName="${targetUser}"
      UserUid="$(id -u "$UserName")"
      RuntimeDir="/run/user/$UserUid"
      BusAddr="unix:path=$RuntimeDir/bus"

      run_as_user() {
        runuser -u "$UserName" -- "${envBin}" \
          XDG_RUNTIME_DIR="$RuntimeDir" DBUS_SESSION_BUS_ADDRESS="$BusAddr" "$@"
      }

      # Logged out
      if [ ! -S "$RuntimeDir/bus" ]; then
        echo "No session bus for $UserName; treating as idle. Rebooting."
        systemctl reboot
        exit 0
      fi

      # Every KWin window that has a (non-empty) class.
      mapfile -t Ids < <(run_as_user "${kdotoolBin}" search --class . 2>/dev/null || true)

      AppCount=0
      for Id in "''${Ids[@]}"; do
        [ -n "$Id" ] || continue
        Class="$(run_as_user "${kdotoolBin}" getwindowclassname "$Id" 2>/dev/null || true)"
        ClassLower="''${Class,,}"
        case "$ClassLower" in
          *plasmashell*|python3.13|"")
            echo "Ignoring window $Id (class: '$Class')"
            ;;
          *)
            AppCount=$((AppCount + 1))
            echo "Counting window $Id (class: '$Class')"
            ;;
        esac
      done

      echo "Open application windows: $AppCount"
      if [ "$AppCount" -eq 0 ]; then
        echo "Nothing open. Rebooting."
        systemctl reboot
      else
        echo "Windows open; skipping nightly reboot."
      fi
    '';
  };
in
{
  systemd.services.nightly-reboot = {
    description = "Reboot at 03:00 if no application windows are open";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe rebootIfIdle;
    };
  };

  systemd.timers.nightly-reboot = {
    description = "Nightly conditional reboot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = false;
      AccuracySec = "1min";
    };
  };
}