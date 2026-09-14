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

  wrapperArgs =
    [ "--add-flags" "--password-store=${cfg.passwordStore}" ]
    ++ [ "--set" "ELECTRON_OZONE_PLATFORM_HINT" ozonePlatform ]
    ++ lib.optionals cfg.wayland [ "--set-default" "CLAUDE_USE_WAYLAND" "1" ];

  wrapped = pkgs.symlinkJoin {
    name = "claude-desktop-wrapped";
    paths = [ cfg.package ];
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
      type = lib.types.enum [ "basic" "gnome-libsecret" "kwallet5" "kwallet6" ];
      default = "gnome-libsecret";
      description = ''
        Credential backend passed to Electron.
      '';
    };

    cowork = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load vhost_vsock, which Cowork's KVM guest needs for host/guest
        transport; there is no /dev/vhost-vsock node until the module is in.
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