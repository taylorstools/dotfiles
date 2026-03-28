{ config, pkgs, lib, self, ... }:

let
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

  # Audio (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Profile icon
  systemd.tmpfiles.rules = [
    "d /var/lib/AccountsService/icons 0755 root root -"
    "C+ /var/lib/AccountsService/icons/taylor 0644 root root ${avatar}"
  ];

  environment.etc."AccountsService/users/taylor".text = ''
    [User]
    Icon=/var/lib/AccountsService/icons/taylor
  '';

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  # User
  users.users.taylor = {
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

  # Packages
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
      flake = "${config.users.users.taylor.home}/.dotfiles/nixos";
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