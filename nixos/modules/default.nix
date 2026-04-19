{ config, pkgs, ... }:

{
  imports = [
    ./components/autoupgrade.nix
    ./components/custom-tela-icons.nix
    ./components/git.nix
    ./components/printing.nix
    ./components/ssh.nix
    ./components/users.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 1;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  time.timeZone = "America/Phoenix";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Power management
  services.upower.enable = true;

  # Disable X11
  services.xserver.enable = false;

  # PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  networking = {
    wireguard.enable = true;
    networkmanager.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  services = {
    flatpak.enable = true;
    samba.enable = true;
    gvfs.enable = true;
  };

  programs = {
    firefox.enable = true;
    bash.enable = true;
  };

  environment.systemPackages = with pkgs; [
    bitwarden-desktop
    chezmoi
    efibootmgr
    eza
    fastfetch
    google-chrome
    gum
    imagemagick
    kitty
    mission-center
    posy-cursors
    python3
    qbittorrent
    vscodium
    wget
    wireguard-tools
    xdg-user-dirs
    zoxide
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    inter
  ];

  system.stateVersion = "25.11";
}