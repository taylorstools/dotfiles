{ config, pkgs, ... }:

{
  # systemd
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 2;

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

  # Disable X11
  services.xserver.enable = false;

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
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    bitwarden-desktop
    chezmoi
    eza
    fastfetch
    gh
    git
    google-chrome
    imagemagick
    inter
    kdePackages.kate
    kitty
    mission-center
    nerd-fonts.jetbrains-mono
    posy-cursors
    qbittorrent
    tela-icon-theme
    vscodium
    zoxide
  ];

  programs.bash = {
    enable = true;
    shellAliases = {
      update = "nix flake update --flake ~/dotfiles/nixos && sudo nixos-rebuild switch --flake ~/dotfiles/nixos#$(hostname)";
    };
  };

  system.stateVersion = "25.11";
}
