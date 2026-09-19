{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.claude-desktop;
  system = pkgs.stdenv.hostPlatform.system;

  # niri exports ELECTRON_OZONE_PLATFORM_HINT=auto for the whole session, which
  # lands this app on Wayland no matter what the option below says. Chromium
  # >= 146 asserts zwp_idle_inhibit_manager_v1 on any open window, with no
  # video, audio or Wake Lock API in play; niri honours it and stops emitting
  # ext-idle-notify, so hypridle never learns the session went idle and nothing
  # dims, locks or blanks. Pin the hint per-app so the option decides.
  ozonePlatform = if cfg.wayland then "wayland" else "x11";

  # Only env vars and Chromium flags reach this build. CLAUDE_USE_WAYLAND and
  # CLAUDE_PASSWORD_STORE are read by upstream's scripts/launcher-common.sh,
  # which only the .deb and .rpm formats install: nix/claude-desktop.nix copies
  # usr/lib and usr/share out of the official .deb and makeWrappers the Electron
  # ELF itself, so no launcher script exists here to interpret them. Setting
  # them is a no-op; the ozone hint and a raw --password-store are the knobs.
  wrapperArgs =
    lib.optionals (cfg.passwordStore != null)
      [ "--add-flags" "--password-store=${cfg.passwordStore}" ]
    ++ [ "--set" "ELECTRON_OZONE_PLATFORM_HINT" ozonePlatform ];

  wrapped = pkgs.symlinkJoin {
    name = "claude-desktop-wrapped";
    paths = [ cfg.package ];

    # symlinkJoin constructs a bare stdenvNoCC derivation, so meta does not
    # come along with the paths: without this the result carries no license
    # or sourceProvenance and reports itself only as claude-desktop-wrapped.
    inherit (cfg.package) meta;

    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude-desktop ${lib.escapeShellArgs wrapperArgs}
    '';
  };
in
{
  options.myOptions.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.claude-desktop.packages.${system}.claude-desktop-fhs;
      defaultText = lib.literalExpression
        "inputs.claude-desktop.packages.\${system}.claude-desktop-fhs";
      description = ''
        Which Claude Desktop build to install. The -fhs variant runs the app
        under bubblewrap inside an FHS environment, which is what lets MCP
        servers shell out to npx, uvx, or docker. It also supplies qemu_kvm,
        an OVMF compat shim and virtiofsd on the paths Cowork probes. The
        plain build does neither.
      '';
    };

    passwordStore = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [ "basic" "gnome-libsecret" "kwallet5" "kwallet6" ]
      );
      default = null;
      description = ''
        Credential backend passed to Electron as --password-store=.

        Left null, Chromium's own os_crypt autodetection owns the decision.
        That is what upstream settled on in #763 ("no default launcher flag
        may shadow an official code path"): the autodetect deliberately
        declines weak persistence on sessions that cannot do better, rather
        than storing tokens unsafely. Set this only as an escape hatch, when
        sign-ins do not survive a restart.
      '';
    };

    cowork = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load vhost_vsock, which Cowork's KVM guest needs for host/guest
        transport; there is no /dev/vhost-vsock node until the module is in.

        This is the whole host-side gate on NixOS. Upstream also warns about
        kvm group membership, but that is a Debianism: nixpkgs leaves
        systemd's dev-kvm-mode at its 0666 default, and the udev rule for
        /dev/vhost-vsock uses the same mode.
      '';
    };

    wayland = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run Electron natively on Wayland rather than through XWayland.

        Leave this off unless the rendering is worth it: on Wayland the app
        holds an idle inhibitor open the entire time its window is, which
        stops hypridle from ever dimming, locking or blanking the screen.
        See the ELECTRON_OZONE_PLATFORM_HINT note at the top of this file.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrapped ];

    boot.kernelModules = lib.optionals cfg.cowork [ "vhost_vsock" ];
  };
}
