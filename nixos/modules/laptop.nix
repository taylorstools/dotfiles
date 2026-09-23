{ pkgs, ... }:

let
  # One set of numbers for both the Plymouth theme and the niri splash: the
  # logo sits in the same place in each, so the handoff between them does
  # not move it. Change them in the shared file, not in either package --
  # htpc.nix draws the same mark from it.
  splashLogo = import ./components/assets/splash-logo.nix;
in
{
  imports = [
    ./components/claude-desktop.nix
    ./components/davinci-resolve.nix
    ./components/dms.nix
    ./components/greetd.nix
    ./components/howdy.nix
    ./components/hyprvoice.nix
    ./components/niri.nix
    ./components/niri-splash
    ./components/power-management.nix
    ./components/roland.nix
    ./components/thunar.nix
  ];

  programs = {
    direnv.enable = true;
    localsend.enable = true;
    nix-ld.enable = true;
    obs-studio.enable = true;
  };

  myOptions = {
    claude-desktop = {
      enable = true;
      passwordStore = "gnome-libsecret";
    };

    dms.source = "stable";

    quickshell.source = "stable";

    hyprvoice = {
      enable = true;

      # nixpkgs' whisper-cpp is CPU-only by default, which on medium.en costs
      # ~20s of silence after you stop talking. The 890M runs the same RADV
      # Vulkan backend Handy picked for itself. Costs a local whisper-cpp
      # build on every nixpkgs bump that touches it.
      package = pkgs.callPackage ../pkgs/hyprvoice/package.nix {
        whisper-cpp = pkgs.whisper-cpp.override { vulkanSupport = true; };
      };

      # The ggml file's own hash: `nix hash file --sri
      # ~/.local/share/hyprvoice/models/whisper/ggml-medium.en.bin` reads it
      # off the copy onboarding already downloaded. config.toml is chezmoi's.
      models."medium.en" = "sha256-zDfpNHgzjsdwAoGnrDChASiSnrj0J92i6GX6qPbaQ1Y=";
    };

    niri-splash = {
      enable = true;
      # The dock is a separate DMS surface and comes up a second or two
      # after the bar; hold the splash for it too.
      namespaces = [ "dms:bar" "dms:dock" ];
    } // splashLogo;
    
    plymouth = {
      enable = true;
      theme = "minimal";
      themePackages = [
        (pkgs.callPackage ../pkgs/plymouth-theme-minimal/package.nix splashLogo)
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    kdePackages.krdc
    moonlight-qt
    obsidian
    vscodium
  ];
}
