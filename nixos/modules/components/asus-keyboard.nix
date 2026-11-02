{ inputs, pkgs, ... }:

{
  imports = [ inputs.asus-px-keyboard-tool.nixosModules.default ];

  services.asus-px-keyboard-tool = {
    enable = true;

    # Two fixes to the tool's BPF program (see the patch): its lookup only
    # matched keys with nothing after the code in their report, and the
    # camera key sends no release, so remapped to one key it stayed held and
    # only the first press registered. The patch turns camera presses into
    # KEY_PROG3 and KEY_PROG1 in turn, so each one is a new press.
    package = inputs.asus-px-keyboard-tool.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./asus-px-keyboard-tool-camera.patch ];
    });

    settings = {
      bpf = {
        enabled = true;
        remaps = [
          { from = 78; to = 153; }   # 0x4e -> 0x99  fn+esc      -> KEY_PROG4
          { from = 126; to = 186; }  # 0x7e -> 0xba  emoji key   -> KEY_PROG2 (XF86Launch2)
          # 0x85 (camera key) is handled in the patch: KEY_PROG3 and KEY_PROG1
          # (XF86Launch3/1) in turn, so 0x38 is taken and the ProArt hub key
          # (0x8b) can't be remapped to it.
          # 0xc7 (kb backlight) needs no remap: it already arrives as XF86KbdLightOnOff.
        ];
      };

      fnlock = {
        enabled = true;
        keycode = "KEY_PROG4";
        boot_default = "last";
      };

      kb_brightness_cycle.enabled = false;
      tablet_kb_backlight_disable.enabled = false;
    };
  };
}