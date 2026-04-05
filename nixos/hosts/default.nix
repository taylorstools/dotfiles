{ config, pkgs, lib, ... }:

let
  username = "taylor";
  avatar = ./taylor.png;
in
{
  # Bootloader
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

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Disable X11
  services.xserver.enable = false;

  services.upower.enable = true;

  # Printing
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.hplip pkgs.hplipWithPlugin ];

  # Audio (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/AccountsService/icons 0755 root root -"

    # Link icon into place (store path -> runtime path)
    "L+ /var/lib/AccountsService/icons/${username} - - - - ${avatar}"

    # Create AccountsService user file
    "f+ /var/lib/AccountsService/users/${username} 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/${username}\\n"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  # User
  users.users.${username} = {
    isNormalUser = true;
    description = "Taylor";
    extraGroups = [ "networkmanager" "wheel" "input" ];
  };

  # Sudo
  security.sudo.wheelNeedsPassword = false;

  # Allow unfree
  nixpkgs.config.allowUnfree = true;

  # Nix features
  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  # Services / Programs
  services.flatpak.enable = true;
  services.samba.enable = true;
  services.gvfs.enable = true;
  programs.firefox.enable = true;
  programs.bash.enable = true;

  programs.git.enable = true;
  programs.git.config = {
    safe.directory = [ "/home/taylor/.dotfiles" ];
  };

  # Packages
  environment.systemPackages = with pkgs; [
    bitwarden-desktop
    chezmoi
    efibootmgr
    eza
    fastfetch
    gh
    google-chrome
    hplip
    imagemagick
    kitty
    mission-center
    posy-cursors
    qbittorrent
    vscodium
    wget
    xdg-user-dirs
    zoxide
  ];

  # Fonts
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
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  # System settings
  system = {
    autoUpgrade = {
      enable = true;
      dates = "daily";
      flake = "${config.users.users.${username}.home}/.dotfiles/nixos";
      flags = [
        "--update-input" "nixpkgs"
      ];
      allowReboot = false;
    };

    stateVersion = "25.11";
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
}