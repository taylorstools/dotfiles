{ config, pkgs, ... }:
let
  powerProfileSwitch = pkgs.writeShellScript "power-profile-switch" ''
    ppctl=${pkgs.power-profiles-daemon}/bin/powerprofilesctl
    systemctl=${pkgs.systemd}/bin/systemctl

    profilesReady() {
      out=$(timeout 5 "$ppctl" list 2>/dev/null) && [ -n "$out" ]
    }

    if ! profilesReady; then
      for attempt in 1 2 3; do
        timeout 30 "$systemctl" restart power-profiles-daemon.service 2>/dev/null || true
        for _ in $(seq 1 10); do
          if profilesReady; then break 2; fi
          sleep 1
        done
      done
    fi

    onAc=0
    for ps in /sys/class/power_supply/*; do
      if [ "$(cat "$ps/type" 2>/dev/null)" = "Mains" ] \
         && [ "$(cat "$ps/online" 2>/dev/null)" = "1" ]; then
        onAc=1
      fi
    done

    if [ "$onAc" = "1" ]; then
      "$ppctl" set performance
    else
      "$ppctl" set power-saver
    fi
  '';
in
{
  systemd.services.power-profile-switch = {
    description = "Set power profile based on AC/battery state";
    path = [ pkgs.coreutils pkgs.power-profiles-daemon ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = powerProfileSwitch;
    };
  };

  # Apply once 45 sec after boot
  systemd.timers.power-profile-switch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "45s";
      Unit = "power-profile-switch.service";
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart power-profile-switch.service"
  '';
}