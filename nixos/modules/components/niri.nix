{ pkgs, lib, ... }:

{
  imports = [
    ./keyd.nix
  ];

  programs.niri.enable = true;
  programs.dconf.enable = true;

  services.gnome.gnome-keyring.enable = true;

  systemd.packages = [ pkgs.libinput-gestures ];

  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.common.default = "gtk";
  };

  nixpkgs.overlays = [
    (final: prev: {
      # niri-session calls `systemctl --user import-environment` and
      # `dbus-update-activation-environment --all` with no variable list, which
      # systemd deprecated - it prints a warning at every login and logout.
      # Spell the names out at runtime: identical behaviour, no warning.
      # Drop once https://github.com/YaLTeR/niri/issues/254 lands upstream.
      niri = prev.niri.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          substituteInPlace $out/bin/niri-session \
            --replace-fail \
              'systemctl --user import-environment' \
              'systemctl --user import-environment $(env | sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p")' \
            --replace-fail \
              'dbus-update-activation-environment --all' \
              'dbus-update-activation-environment $(env | sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p")'
        '';
      });
    })
  ];

  # The lid-close bind in dot_config/niri/custom/misc.kdl locks the session and
  # then runs `sleep 1; systemctl suspend` itself. logind's own default,
  # HandleLidSwitch=suspend, acts on the same lid event and gets there first:
  # the machine is already asleep while the bind is still inside `sleep 1`.
  # CLOCK_MONOTONIC stands still through suspend, so that second runs out only
  # after the lid opens - and its `systemctl suspend` puts the laptop straight
  # back to sleep a moment after it woke. That second suspend is the screen
  # and keyboard going dark right after opening the lid.
  #
  # Hold logind's lid handling for as long as niri is up, so the bind is the
  # only thing acting on the lid (the same inhibitor GNOME and KDE take). At
  # the greeter or a TTY nothing holds it, and logind suspends on its own.
  # Check with: systemd-inhibit --list
  systemd.user.services.niri-lid-inhibit = {
    description = "Hold logind lid handling while niri handles the lid";
    wantedBy = [ "niri.service" ];
    bindsTo = [ "niri.service" ];
    after = [ "niri.service" ];
    serviceConfig = {
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.systemd}/bin/systemd-inhibit"
        "--what=handle-lid-switch"
        "--who=niri"
        # Quoted for systemd's ExecStart parser, which splits on spaces.
        "\"--why=niri's lid-close bind locks and suspends\""
        "--mode=block"
        "${lib.getExe' pkgs.coreutils "sleep"} infinity"
      ];
      Restart = "on-failure";
    };
  };

  environment.systemPackages = with pkgs; [
    brightnessctl
    fd
    fzf
    ghostty
    gnome-calculator
    gparted
    grim
    gsettings-desktop-schemas
    libnotify # notify-send, for snipping-tool.sh's clipboard/save notification
    librsvg # rsvg-convert, for niri_window-switcher.sh's SVG icons
    loupe
    nwg-look
    python3
    showtime
    slurp
    wl-clipboard
    wlogout
    wlr-which-key
    xed-editor
    xsettingsd
    xwayland-satellite
    yad
  ];
}