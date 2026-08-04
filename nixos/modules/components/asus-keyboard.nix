{ inputs, ... }:

{
  imports = [ inputs.asus-px-keyboard-tool.nixosModules.default ];

  services.asus-px-keyboard-tool = {
    enable = true;

    settings = {
      bpf = {
        enabled = true;
        remaps = [
          { from = 78; to = 153; }   # 0x4e -> 0x99  fn+esc      -> KEY_PROG4
          # { from = 126; to = 186; } # 0x7e -> 0xba  emoji key   -> KEY_PROG2
          # { from = 139; to = 56;  } # 0x8b -> 0x38  proart hub  -> KEY_PROG1
          # { from = 199; to = 92;  } # 0xc7 -> 0x5c  kb backlight-> KEY_PROG3
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