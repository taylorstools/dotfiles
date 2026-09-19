{ config, pkgs, inputs, lib, ... }:

let
  cfg = config.myOptions;
  system = pkgs.stdenv.hostPlatform.system;

  dmsPkg =
    if cfg.dms.source == "git"
    then inputs.dms.packages.${system}.dms-shell
    else pkgs.dms-shell;

  quickshellPkg =
    if cfg.quickshell.source == "git"
    then inputs.quickshell.packages.${system}.default
    else pkgs.quickshell;

  # nixpkgs' dms-shell installs the app icon to
  # $out/share/hicolor/scalable/apps/danklogo.svg. That path is missing its
  # `icons/` component, so it lands outside every XDG icon search path, and
  # nothing can resolve the `Icon=` key of the desktop entry the same
  # derivation installs. Upstream's own flake installs to
  # share/icons/hicolor/scalable/apps/ and gets this right - it is the only
  # packaging difference between the two derivations that changes runtime
  # behaviour. Everything resolving an icon through DesktopEntries ->
  # Paths.getAppIcon() comes up empty for DMS's own windows as a result,
  # including the DankBar running-apps widget, which then falls back to
  # drawing the first letter of the app name. The dock is unaffected because
  # it maps DMS windows to built-in "core apps" by title and uses their
  # bundled icons instead.
  #
  # The icon NAME is version-dependent: v1.6.1's com.danklinux.dms.desktop
  # declares `Icon=danklogo`, and master renamed that to
  # `Icon=com.danklinux.dms` in the same commit that added
  # assets/com.danklinux.dms.svg. Install both names so the entry resolves
  # whichever release nixos-unstable happens to be carrying, and so a bump
  # across that rename doesn't silently break it again.
  #
  # Shipped as its own package rather than an overrideAttrs on dms-shell: an
  # override changes the derivation hash and costs a full local Go rebuild on
  # every nixpkgs bump, for the sake of two 13KB files.
  #
  # Self-disabling per name: if nixpkgs ever fixes the install path, this
  # produces no file for that name instead of colliding with dms-shell.
  dmsIconFix = pkgs.runCommand "dms-shell-icon-fix" { } ''
    mkdir -p "$out"

    install_icon() {
      local name="$1"
      shift

      if [ -e "${dmsPkg}/share/icons/hicolor/scalable/apps/$name.svg" ]; then
        echo "dms-shell already installs $name.svg correctly; skipping."
        return 0
      fi

      local candidate
      for candidate in "$@"; do
        if [ -f "$candidate" ]; then
          install -Dm444 "$candidate" \
            "$out/share/icons/hicolor/scalable/apps/$name.svg"
          return 0
        fi
      done

      # Warn rather than fail: a moved asset should not take a nixos-rebuild
      # down over a missing icon.
      echo "dms-shell-icon-fix: no source for $name.svg; skipping." >&2
    }

    install_icon danklogo \
      "${dmsPkg.src}/core/assets/danklogo.svg" \
      "${dmsPkg.src}/quickshell/assets/danklogo.svg"

    install_icon com.danklinux.dms \
      "${dmsPkg.src}/assets/com.danklinux.dms.svg" \
      "${dmsPkg.src}/quickshell/assets/danklogo2.svg"
  '';
in
{
  options.myOptions = {
    dms.source = lib.mkOption {
      type = lib.types.enum [ "stable" "git" ];
      default = "stable";
      description = "Where to source the DankMaterialShell package from.";
    };

    quickshell.source = lib.mkOption {
      type = lib.types.enum [ "stable" "git" ];
      default = "stable";
      description = "Where to source the quickshell package from.";
    };
  };

  config = {
    programs.dank-material-shell = {
      enable = true;
      package = dmsPkg;
      quickshell.package = quickshellPkg;

      systemd = {
        enable = true;
        restartIfChanged = true;
      };

      enableDynamicTheming = true;
      enableClipboardPaste = true;
    };

    environment.systemPackages = with pkgs; [
      accountsservice
      adw-gtk3
      # Also installs hypridle.service into /etc/systemd/user, which is
      # WantedBy=graphical-session.target. That unit is what runs hypridle -
      # nothing spawns it from niri. See dot_config/niri/custom/startup.kdl.
      hypridle
      swaybg
    ]
    # Only the nixpkgs derivation is missing the icon; the flake gets it right.
    ++ lib.optional (cfg.dms.source == "stable") dmsIconFix;

    # That packaged unit pins Environment=PATH to hypridle's own closure and
    # nothing else: hyprland, hyprlock, procps, coreutils, findutils, gnugrep,
    # gnused, systemd. Every script under ~/scripts/hypridle is
    # #!/usr/bin/env bash, and bash is not on that list, so all of them die
    # with `env: 'bash': No such file or directory` before their first line -
    # silently, since hypridle only logs that the process was created. niri,
    # dms and brightnessctl are missing from it too, so the dim and lock paths
    # would fail on their first real command even with a shell. Put the system
    # profile back: a drop-in is parsed after the unit, and the later
    # assignment of a variable wins.
    systemd.user.services.hypridle = {
      overrideStrategy = "asDropin";
      serviceConfig.Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };
  };
}