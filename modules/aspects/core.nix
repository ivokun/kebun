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
      # Disable the editor: anyone at the keyboard could otherwise edit the
      # kernel command line and bypass the LUKS passphrase entirely
      # (init=/bin/sh). FIDO/TPM disk encryption is meaningless if the boot
      # menu can inject its own cmdline. Rebooting to a generation is still
      # possible via the reboot-into-menu entry.
      systemd-boot.editor = false;
      efi.canTouchEfiVariables = true;
    };

    # Machine-specific initramfs/kernel modules and kernelParams are declared
    # per host in hosts/<name>/default.nix.

    supportedFilesystems = ["btrfs" "vfat" "exfat" "nfs"];

    # ─── Plymouth boot splash ───
    # Kebun theme re-skinned at build time from lib/palette.nix: Rose Pine
    # Dawn light base, IVOKUN wordmark (same derivation as the SDDM
    # greeter's). When TPM2 auto-unlock fails, Plymouth shows the styled
    # password prompt instead of dropping to a raw TTY.
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
  # NOTE: The persistent swap device is a dedicated LUKS-encrypted partition.
  # It was intended as a hibernation resume target, but hibernation is disabled
  # because swap is smaller than RAM — see hosts/sakura/default.nix. The device
  # stays in hardware-configuration.nix to avoid merge conflicts.
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
      # Trusted Nix clients can override daemon safety policy and are therefore
      # root-equivalent. Interactive administrators use sudo when it is needed.
      trusted-users = lib.mkForce ["root"];
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

  # ─── locate ───
  # plocate was installed as a bare package, which meant `locate` was on PATH
  # but its database was never built — every query returned nothing. The
  # service is what schedules updatedb.
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };

  # Don't spin the disk rebuilding the index on battery (mirrors Omarchy's
  # plocate-ac-only drop-in). The NixOS module owns update-locatedb — the
  # upstream plocate units (plocate-updatedb.*) are never installed here.
  systemd.services.update-locatedb.unitConfig.ConditionACPower = true;

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
