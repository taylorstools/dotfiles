{ config, pkgs, inputs, lib, ... }:

# What Taylor's own Quickshell config (~/.dotfiles/.quickshell) needs on the
# system. The config itself lives in the dotfiles and is started by the
# chezmoi-managed user unit ~/.config/systemd/user/quickshell.service.
let
  cfg = config.myOptions;
  system = pkgs.stdenv.hostPlatform.system;

  quickshellUnwrapped =
    if cfg.quickshell.source == "git"
    then inputs.quickshell.packages.${system}.default
    else pkgs.quickshell;

  # The notepad's Open/Save As use Qt's file dialog, which the gtk3 platform
  # theme shows as GTK's file chooser inside the shell. Without GTK's
  # GSettings schemas that aborts the whole shell. Appended, not prepended:
  # apps the shell launches inherit this and keep their own schemas first.
  quickshellPkg = pkgs.symlinkJoin {
    name = "quickshell-with-gtk-schemas";
    paths = [ quickshellUnwrapped ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in $out/bin/qs $out/bin/quickshell; do
        wrapProgram "$bin" --suffix XDG_DATA_DIRS : "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
      done
    '';
  };
in
{
  options.myOptions.quickshell.source = lib.mkOption {
    type = lib.types.enum [ "stable" "git" ];
    default = "stable";
    description = "Where to source the quickshell package from.";
  };

  config = {
    environment.systemPackages = with pkgs; [
      quickshellPkg # qs
      adw-gtk3
      brightnessctl # backlight and keyboard light
      fd # runner: searching below a folder
      fzf # runner: ranking matches
      grim # snipping tool
      libnotify # notify-send, for scripts' messages
      matugen # colours from the wallpaper, and the app themes
      python3 # Theming/term16.py
      slurp # snipping tool: region select
      unicode-emoji # emoji picker: emoji-test.txt, the list and names
      wl-clipboard # clipboard history
      wl-gammarelay-rs # night light (Services/NightLight.qml)
      wtype # clipboard history and emoji picker: type into the focused app
      xdg-utils # runner: xdg-open, xdg-mime
    ];

    # The emoji picker reads /run/current-system/sw/share/unicode/emoji.
    environment.pathsToLink = [ "/share/unicode" ];

    # The icon font.
    fonts.packages = [ pkgs.material-symbols ];

    # The camera key (Services/Camera.qml) switches webcams off by
    # deauthorizing their video interfaces, which needs write access to each
    # one's `authorized` file, and back on by re-probing them through
    # drivers_probe (authorizing an interface again doesn't rebind its
    # driver). Interfaces rather than the whole device: the PX13's webcam
    # also carries the light and presence sensors on a HID interface, and
    # those should keep working with the camera off. wheel is Taylor's own
    # group here; using it avoids a new group and a re-login.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTR{bInterfaceClass}=="0e", RUN+="${pkgs.coreutils}/bin/chgrp wheel /sys%p/authorized", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/authorized"
    '';
    systemd.tmpfiles.rules = [
      "z /sys/bus/usb/drivers_probe 0220 root wheel -"
    ];

    # The control center's profile picture (/var/lib/AccountsService/icons).
    services.accounts-daemon.enable = true;
    # The shell is the session's polkit agent (Polkit/PolkitDialog.qml).
    security.polkit.enable = true;

    # The lock screen (Lock/Lock.qml) authenticates against this.
    security.pam.services.quickshell = { };
  };
}
