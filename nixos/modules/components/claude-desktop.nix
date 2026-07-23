{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.myOptions.claude-desktop;
  system = pkgs.stdenv.hostPlatform.system;
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
        Which Claude Desktop build to install. The -fhs variant wraps the app
        in an FHS env so MCP servers can shell out to npx, uvx, or docker.
      '';
    };

    wayland = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run Electron natively on Wayland instead of XWayland.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    environment.sessionVariables = lib.mkIf cfg.wayland {
      CLAUDE_USE_WAYLAND = "1";
    };
  };
}