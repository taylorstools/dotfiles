{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.claude-desktop;
  system = pkgs.stdenv.hostPlatform.system;

  wrapperArgs =
    [ "--add-flags" "--password-store=${cfg.passwordStore}" ]
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
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrapped ];

    boot.kernelModules = lib.optionals cfg.cowork [ "vhost_vsock" ];
  };
}