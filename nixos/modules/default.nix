{ config, pkgs, ... }:

{
  imports = [
    ./components/autoupgrade.nix
    ./components/custom-tela-icons.nix
    ./components/desktop-graphics.nix
    ./components/flatpak.nix
    ./components/fonts.nix
    ./components/git.nix
    ./components/gpu-amd.nix
    ./components/gpu-intel.nix
    ./components/gpu-nvidia.nix
    ./components/linux-kernel.nix
    ./components/mission-center.nix
    ./components/plymouth.nix
    ./components/printing.nix
    ./components/secure-boot.nix
    ./components/ssh.nix
    ./components/sunshine.nix
    ./components/tailscale.nix
    ./components/timeouts.nix
    ./components/update-alias.nix
    ./components/users.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "flakes" "nix-command" ];
    # Build parallelism. Left at "auto" this is one job per logical core.
    max-jobs = 4;
    cores = 6;
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;
    timeout = 1;
  };

  # Cap the ZFS ARC at 8 GiB. Set on the kernel command line so it also
  # applies to the module loaded in the initrd.
  boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];

  # Compressed swap in RAM, so the kernel can reclaim anonymous memory
  # instead of OOM-killing under pressure.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  boot.zfs.forceImportRoot = false;
  services.zfs.autoScrub.enable = true;

  myOptions.linuxKernel.variant = "latest-zfs";

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

  # PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  networking.networkmanager.enable = true;

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
    gvfs.enable = true;
    samba.enable = true;
    upower.enable = true;
    xserver.enable = false;
  };

  programs = {
    bash.enable = true;
    firefox.enable = true;
  };

  environment.systemPackages = with pkgs; [
    bitwarden-desktop
    chezmoi
    efibootmgr
    eza
    (fastfetch.override { zfsSupport = true; })
    google-chrome
    gum
    imagemagick
    jq
    kitty
    pciutils
    posy-cursors
    python3
    qbittorrent
    ripgrep
    unzip
    vlc
    wget
    xdg-user-dirs
    zoxide
  ];

  system.stateVersion = "25.11";
}