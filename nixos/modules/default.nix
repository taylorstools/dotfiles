{ config, pkgs, ... }:

{
  imports = [
    ./components/autoupgrade.nix
    ./components/custom-tela-icons.nix
    ./components/git.nix
    ./components/ssh.nix
    ./components/user.nix
  ];

  # Allow unfree
  nixpkgs.config.allowUnfree = true;

  # Nix features
  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 1;
  };

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

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

  # Networking
  networking.networkmanager.enable = true;

  # Power management
  services.upower.enable = true;

  # Disable X11
  services.xserver.enable = false;

  # Audio (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

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

  # Printing
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.hplip pkgs.hplipWithPlugin ];

  # Services/programs
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
    google-chrome
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

  system.stateVersion = "25.11";
}