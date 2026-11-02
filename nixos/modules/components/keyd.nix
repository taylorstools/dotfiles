{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards.default = {
      # Leave the PX13's hotkey device (fn keys, emoji, camera) alone: keyd
      # grabbing it hides those keys from asus-px-keyboard-tool, and the
      # emoji and camera keys never reached niri through keyd. The last part
      # of the id is keyd's hash of the device's name and how many keys it
      # advertises, so a kernel that maps new keys changes it (it was
      # 98a603e5 before). Both halves of the keyboard are "N-KEY Device" in
      # `journalctl -b -u keyd`; the hotkey one has fewer keys, and in
      # /proc/bus/input/devices it's the one with rfkill and no leds.
      ids = [ "*" "-0b05:19b6:23100d26" ];
      settings.main = {
        leftmeta = "overload(meta, macro(leftmeta+d))";
      };
    };
  };
}