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
      accountsservice
      adw-gtk3
      brightnessctl # backlight and keyboard light
      fd # runner: searching below a folder
      fzf # runner: ranking matches
      hypridle
      libnotify # notify-send, for scripts' messages
      matugen # colours from the wallpaper, and the app themes
      swaybg
      wl-clipboard # clipboard history
      wlsunset # night light
      wtype # clipboard history: paste into the focused app
    ];

    # The icon font.
    fonts.packages = [ pkgs.material-symbols ];

    # The control center's profile picture (/var/lib/AccountsService/icons).
    services.accounts-daemon.enable = true;
    # The shell is the session's polkit agent (Polkit/PolkitDialog.qml).
    security.polkit.enable = true;

    # The lock screen (Lock/Lock.qml) authenticates against this.
    security.pam.services.quickshell = { };

    # hypridle's dim/restore scripts call brightnessctl, qs and friends.
    systemd.user.services.hypridle = {
      overrideStrategy = "asDropin";
      serviceConfig.Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };
  };
}
