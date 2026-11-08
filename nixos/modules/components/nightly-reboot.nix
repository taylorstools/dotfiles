{ config, pkgs, lib, ... }:

let
  targetUser = config.myOptions.user.name;

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

      # kdotool >= 0.3.0 refuses to run unless KDE_SESSION_VERSION=6 is set,
      # and a system service doesn't inherit the Plasma session environment.
      run_as_user() {
        runuser -u "$UserName" -- "${envBin}" \
          XDG_RUNTIME_DIR="$RuntimeDir" DBUS_SESSION_BUS_ADDRESS="$BusAddr" \
          KDE_SESSION_VERSION=6 "$@"
      }

      # Logged out
      if [ ! -S "$RuntimeDir/bus" ]; then
        echo "No session bus for $UserName; treating as idle. Rebooting."
        systemctl reboot
        exit 0
      fi

      # Every KWin window that has a (non-empty) class. kdotool's stderr is
      # left alone so failures land in the journal.
      if ! SearchOut="$(run_as_user "${kdotoolBin}" search --class .)"; then
        echo "kdotool search failed; can't tell what's open. Skipping nightly reboot."
        exit 0
      fi
      mapfile -t Ids <<< "$SearchOut"

      TotalCount=0
      AppCount=0
      for Id in "''${Ids[@]}"; do
        [ -n "$Id" ] || continue
        TotalCount=$((TotalCount + 1))
        Class="$(run_as_user "${kdotoolBin}" getwindowclassname "$Id")" || Class=""
        ClassLower="''${Class,,}"
        case "$ClassLower" in
          *plasmashell*|python3*)
            echo "Ignoring window $Id (class: '$Class')"
            ;;
          "")
            AppCount=$((AppCount + 1))
            echo "Window $Id has no readable class; counting it to be safe"
            ;;
          *)
            AppCount=$((AppCount + 1))
            echo "Counting window $Id (class: '$Class')"
            ;;
        esac
      done

      # A live Plasma session always has plasmashell windows, so zero windows
      # total means the query broke, not that the machine is idle.
      if [ "$TotalCount" -eq 0 ]; then
        echo "kdotool returned no windows at all (not even plasmashell). Skipping nightly reboot."
        exit 0
      fi

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