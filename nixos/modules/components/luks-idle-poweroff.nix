{ config, lib, ... }:

let
  cfg = config.myOptions.luksIdlePoweroff;
in
{
  options.myOptions.luksIdlePoweroff = {
    enable = lib.mkEnableOption
      "powering off when the LUKS passphrase prompt sits with no input for too long";

    timeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        Seconds the initrd may sit at a passphrase prompt with no keyboard,
        mouse or other input before the machine powers off. Any input event
        restarts the count, so typing slowly or retrying a wrong passphrase
        never trips it; only walking away does.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Stuck at the prompt means a systemd ask-password request is open:
    # systemd-cryptsetup writes /run/systemd/ask-password/ask.* while it
    # waits, and Plymouth (or the console agent) and clevis-luks-askpass all
    # answer it from there. The idle clock only runs while one exists, so
    # time spent waiting on the network for clevis, or on a slow disk, does
    # not count against it.
    #
    # Activity is read straight from evdev. Readers there are not exclusive -
    # Plymouth opens the same nodes without EVIOCGRAB - so every keypress
    # reaches both the prompt and this watcher. New nodes are picked up each
    # tick, which covers a USB keyboard that enumerates late or is plugged in
    # at the prompt.
    boot.initrd.systemd.services.luks-idle-poweroff = {
      description = "Power off after ${toString cfg.timeout}s idle at the LUKS prompt";
      wantedBy = [ "initrd.target" ];

      # Default dependencies would order this after sysinit.target, which
      # waits for cryptsetup.target - so it would only start once the disk
      # was already open. Stopped at switch-root so nothing outlives stage 1.
      unitConfig.DefaultDependencies = false;
      conflicts = [ "initrd-switch-root.target" "shutdown.target" ];
      before = [ "initrd-switch-root.target" "shutdown.target" ];

      # jobScripts land in the initrd on their own, and coreutils (dd, sleep)
      # is part of the default initrdBin.
      script = ''
        Timeout=${toString cfg.timeout}
        StateDir=/run/luks-idle-poweroff
        Stamp="$StateDir/last-input"
        mkdir -p "$StateDir"

        declare -A Watchers=()

        # Seconds since boot. Monotonic, unlike the RTC, which systemd may
        # still be stepping this early.
        uptime_seconds() {
          local Up _
          read -r Up _ < /proc/uptime
          printf '%s\n' "''${Up%.*}"
        }

        # evdev only hands out whole input_event structs, so a 4 KiB dd read
        # returns whatever events are queued and blocks until there are some.
        watch_device() {
          while dd bs=4096 count=1 status=none of=/dev/null; do
            uptime_seconds > "$Stamp"
          done < "$1"
        }

        prompt_open() {
          local Ask
          for Ask in /run/systemd/ask-password/ask.*; do
            [ -e "$Ask" ] && return 0
          done
          return 1
        }

        PromptSince=""
        LastInput=0

        while true; do
          for Dev in /dev/input/event*; do
            [ -c "$Dev" ] || continue
            if [ -n "''${Watchers[$Dev]:-}" ] && kill -0 "''${Watchers[$Dev]}" 2>/dev/null; then
              continue
            fi
            watch_device "$Dev" &
            Watchers[$Dev]=$!
          done

          if prompt_open; then
            Now="$(uptime_seconds)"
            if [ -z "$PromptSince" ]; then
              PromptSince="$Now"
              echo "Passphrase prompt open; powering off after ''${Timeout}s without input."
            fi

            if [ -s "$Stamp" ] && read -r Value < "$Stamp" && [ -n "$Value" ]; then
              LastInput="$Value"
            fi

            IdleFrom="$PromptSince"
            if [ "$LastInput" -gt "$IdleFrom" ]; then
              IdleFrom="$LastInput"
            fi

            if [ $((Now - IdleFrom)) -ge "$Timeout" ]; then
              echo "No input at the passphrase prompt for ''${Timeout}s. Powering off."
              systemctl --no-block poweroff
              exit 0
            fi
          else
            PromptSince=""
          fi

          sleep 1
        done
      '';
    };
  };
}
