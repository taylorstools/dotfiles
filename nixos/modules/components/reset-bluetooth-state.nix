# reset-bluetooth-state.nix
#
# Keeps Plasma from switching the Bluetooth adapter off at login.
#
#   Logs:  journalctl --user -u bluedevil-reset-power
#   State: ~/.config/bluedevilglobalrc ([Adapters] <mac>_powered=...)
#
# Bluedevil (Plasma's Bluetooth kded module) saves each adapter's power state
# when the session ends and restores it at the next login, which overrides
# hardware.bluetooth.powerOnBoot. On a reboot BlueZ can take the adapter down
# before Plasma exits, so Bluedevil records it as powered=false and turns it
# off again on the way back up. The nightly 3am reboot on livingroompc made
# this a regular occurrence, leaving the Xbox controller unable to connect.
#
# This rewrites any saved power-off back to on before kded starts, so the
# adapter stays the way BlueZ brought it up. Turning Bluetooth off by hand
# only lasts until the next login, which is fine for these machines.

{ pkgs, ... }:

{
  systemd.user.services.bluedevil-reset-power = {
    description = "Clear Bluedevil's saved adapter power-off state before Plasma starts";
    wantedBy = [ "graphical-session-pre.target" ];
    before = [ "graphical-session-pre.target" "plasma-kded6.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Leading "-": a missing bluedevilglobalrc (first login) is not a failure.
      ExecStart = "-${pkgs.gnused}/bin/sed -i 's/_powered=false$/_powered=true/' %h/.config/bluedevilglobalrc";
    };
  };
}
