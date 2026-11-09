{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards.default = {
      # Leave the PX13's hotkey device (fn keys, emoji, camera) alone: keyd
      # grabbing it hides those keys from asus-px-keyboard-tool, and the
      # emoji and camera keys never reached niri through keyd. The last part
      # of the id is keyd's hash of the device's name and how many keys it
      # advertises, so it changes with the kernel: 7.2 names both halves
      # "ASUSTeK Computer Inc. N-KEY Device" and the hotkey one is 23100d26;
      # 6.18 names them "Asus Keyboard" and it's 98a603e5. Both are listed so
      # either kernel works. Check `journalctl -b -u keyd` after a kernel
      # change: the hotkey half has fewer keys, and in /proc/bus/input/devices
      # it's the one with rfkill and no leds.
      ids = [ "*" "-0b05:19b6:23100d26" "-0b05:19b6:98a603e5" ];
      settings.main = {
        leftmeta = "overload(meta, macro(leftmeta+d))";
      };
    };
  };
}