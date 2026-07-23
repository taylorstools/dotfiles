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
        servers shell out to npx, uvx, or docker. The plain build cannot.
      '';
    };

    passwordStore = lib.mkOption {
      type = lib.types.enum [ "basic" "gnome-libsecret" "kwallet5" "kwallet6" ];
      default = "gnome-libsecret";
      description = ''
        Credential backend passed to Electron. Electron picks this by sniffing
        XDG_CURRENT_DESKTOP and only recognizes GNOME and KDE. Under niri it
        sees "niri", falls back to "basic" (in-memory plaintext), and drops the
        sign-in on every restart. Setting it explicitly routes credentials
        through the Secret Service API to gnome-keyring, which niri.nix already
        enables and greetd.nix already unlocks via the hyprlock PAM stack.
      '';
    };

    wayland = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run Electron natively on Wayland rather than through XWayland. Opt-in,
        matching the launcher's own default, since native Wayland can bring
        fractional-scaling and IME quirks.

        Note this does not fix Quick Entry: the Ctrl+Alt+Space global hotkey
        needs the GlobalShortcuts portal under native Wayland, which niri does
        not provide. Bind it in niri/custom/binds.kdl instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrapped ];
  };
}