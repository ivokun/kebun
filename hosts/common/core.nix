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
      # s0ix resume fixes for AMD Renoir (ThinkPad X13 Gen 1)
      "amdgpu.dcdebugmask=0x10" # Disable PSR — prevents black screen on resume
      "acpi_sleep=nonvs" # Prevent ACPI NVS corruption during s0ix
      "processor.max_cstate=5" # Limit C-states to prevent s0ix resume failures
      # Prefer S3 (deep) over s2idle. Renoir s2idle deadlocks on suspend
      # re-entry while a previous resume is still in flight (3 fatal hangs
      # in 10 days, 2026-08 — all lid-triggered, journal ends at
      # "Performing sleep operation"). INERT until BIOS Sleep State is set
      # to "Linux" (Config → Power); without that, deep isn't advertised.
      # Verify after BIOS flip: cat /sys/power/mem_sleep → s2idle [deep]
      "mem_sleep_default=deep"
    ];

    # ─── Plymouth boot splash ───
    # Custom kebun theme with ivokun branding (cyan bg + yellow accents).
    # When TPM2 auto-unlock fails, Plymouth shows a styled password prompt
    # instead of dropping to a raw TTY.
    plymouth = {
      enable = true;
      theme = "kebun";
      themePackages = [(pkgs.callPackage ../../packages/plymouth-theme-kebun {})];
    };
  };

  # ─── Swap ───
  # Primary: zram (compressed in-memory swap)
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
  # NOTE: The persistent swap device (a dedicated LUKS-encrypted partition,
  # also the hibernation resume target — see hosts/sakura/default.nix) is
  # defined in hardware-configuration.nix to avoid merge conflicts.
  # Do NOT add swapDevices here.

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

  # ─── File Descriptor Limits ───
  boot.kernel.sysctl = {
    "fs.file-max" = 2097152;
    "fs.inotify.max_user_watches" = 524288;

    # Last-resort escape hatch: sync + remount-ro + signal + reboot
    # (16 + 32 + 64 + 128). The kernel default here is 16, sync only, so
    # Alt+SysRq+B did nothing and every wedged session on this machine ended
    # with a held power button — an unsynced power cut, which is why most of
    # those boots have no shutdown markers in the journal at all.
    #
    # SysRq is a kernel *input filter*, registered ahead of evdev in
    # /proc/bus/input/handlers, so it still works when the compositor has
    # stopped dispatching keys — which on Hyprland 0.54.0 is the case whenever
    # there are no enabled outputs (CKeybindManager::onKeyEvent returns early
    # while m_unsafeState, before it can reach even the VT-switch handling).
    # Alt+SysRq+S, then U, then B is a clean synced reboot.
    #
    # Not a meaningful weakening: it needs physical access to the keyboard, and
    # anyone at the keyboard can already cut power. The disks are LUKS.
    "kernel.sysrq" = 240;
  };

  security.pam.loginLimits = [
    {
      domain = "@users";
      type = "soft";
      item = "nofile";
      value = "524288";
    }
    {
      domain = "@users";
      type = "hard";
      item = "nofile";
      value = "2097152";
    }
  ];
}
