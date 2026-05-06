{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # ─── Boot ───
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "uas" "sd_mod" "btrfs"];
      kernelModules = ["amdgpu" "kvm-amd"];
    };

    kernelModules = ["amdgpu" "kvm-amd" "btusb" "thinkpad_acpi"];

    supportedFilesystems = ["btrfs" "vfat" "exfat" "nfs"];

    # Kernel parameters for LUKS + BTRFS + AMD
    kernelParams = [
      "amd_iommu=on"
      "amdgpu.sg_display=0"
      "rtc_cmos.use_acpi_alarm=1"
    ];

    # ─── Plymouth boot splash ───
    # Replaces text boot messages with a graphical splash.
    # When TPM2 auto-unlock fails, Plymouth shows a styled password prompt
    # instead of dropping to a raw TTY. Purely cosmetic but matches Omarchy.
    plymouth = {
      enable = true;
      theme = "spinner";
    };
  };

  # ─── Swap ───
  # Primary: zram (compressed in-memory swap)
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
  # NOTE: Fallback swapfile is defined in hardware-configuration.nix
  # to avoid merge conflicts. Do NOT add swapDevices here.

  # ─── Locale / Time ───
  time.timeZone = "Asia/Tokyo";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
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
  };

  # ─── Console ───
  console = {
    # ter-116n for comfortable size on 1080p display
    font = "${pkgs.terminus_font}/share/consolefonts/ter-116n.psf.gz";
    keyMap = "us";
  };

  # ─── Nix Settings ───
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = true;
      substituters = [
        "https://cache.nixos.org"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxQMzO+MR5HsMYwJfn+BFMQjEnJPSIlWM+NLSo60="
      ];
      trusted-users = ["root" "@wheel"];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    registry.nixpkgs.flake = inputs.nixpkgs;
  };

  nixpkgs.config.allowUnfree = true;

  # ─── Sound ───
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # ─── SSD Trim ───
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # ─── Firmware Updates ───
  services.fwupd.enable = true;

  # ─── System Packages ───
  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    pciutils
    usbutils
    lm_sensors
  ];

  system.stateVersion = "25.05";
}
