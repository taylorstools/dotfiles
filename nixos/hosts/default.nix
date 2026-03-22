{ config, pkgs, lib, ... }:

{
  # systemd
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 1;

  # Networking
  networking.networkmanager.enable = true;

  # Time zone
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

  # Linux kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Disable X11
  services.xserver.enable = false;

  services.upower.enable = true;

  # Enable printing
  services.printing.enable = true;

  # Enable pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Taylor user
  users.users.taylor = {
    isNormalUser = true;
    description = "Taylor";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Don't require password to use sudo
  security.sudo.wheelNeedsPassword = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  # Common applications and services
  services.flatpak.enable = true;
  services.samba.enable = true;
  services.gvfs.enable = true;
  programs.firefox.enable = true;
  programs.bash.enable = true;

  environment.systemPackages = with pkgs; [
    bitwarden-desktop
    chezmoi
    efibootmgr
    eza
    fastfetch
    gh
    git
    google-chrome
    imagemagick
    kitty
    mission-center
    posy-cursors
    qbittorrent
    tela-icon-theme
    vscodium
    wget
    zoxide
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    inter
  ];

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # Shows battery charge of connected devices on supported
        # Bluetooth adapters. Defaults to 'false'.
        Experimental = true;
        # When enabled other devices can connect faster to us, however
        # the tradeoff is increased power consumption. Defaults to
        # 'false'.
        FastConnectable = true;
      };
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };

  system.stateVersion = "25.11";
}