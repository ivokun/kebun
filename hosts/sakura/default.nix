{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  # ─── AMD APU (Renoir / Ryzen 5 PRO 4650U) ───
  services.xserver.videoDrivers = ["amdgpu"];

  # ─── Machine-specific kernel wiring (ThinkPad X13 Gen 1, AMD Renoir) ───
  # Moved out of modules/aspects/core.nix: these values are sakura-only
  # (ThinkPad/Renoir hardware), so they belong here instead of a shared
  # aspect. Lists kept verbatim from the old core.nix.
  boot.initrd = {
    availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "uas"
      "sd_mod"
      "btrfs"
      # TPM2 (auto-unlock)
      "tpm_crb"
      "tpm_tis"
    ];
    kernelModules = ["amdgpu" "kvm-amd"];
  };

  # vhost_vsock: Cowork (claude-desktop's VM) needs /dev/vhost-vsock.
  # rtsx_pci: SD card reader (Realtek RTS525A).
  boot.kernelModules = [
    "amdgpu"
    "kvm-amd"
    "btusb"
    "thinkpad_acpi"
    "vhost_vsock"
    "rtsx_pci"
  ];

  # Kernel parameters for LUKS + BTRFS + AMD
  boot.kernelParams = [
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

  # ─── Kebun host surface (consumed by Home Manager via osConfig) ───
  kebun.host = {
    isLaptop = true;
    greeterLayout = "jp";
    monitorsLua = ''
      -- Kebun monitor layout — moved verbatim from home/sakura.nix (ADR-0007
      -- Stage 3). sakura-specific values (X13 built-in panel + HDMI + 4K DP);
      -- verify against the machine on next deploy — backlog §3.1.
      hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
      hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.00", position = "2272x1440", scale = 1.00 })
      hl.monitor({ output = "DP-2", mode = "3840x2160@60.00", position = "1920x0", scale = 1.5 })
    '';
  };

  # ─── LUKS TPM2 auto-unlock ───
  # Use systemd initrd so crypttab supports tpm2-device=auto
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-5525027e-a087-470e-a530-3ab692f4a14c" = {
    device = "/dev/disk/by-uuid/5525027e-a087-470e-a530-3ab692f4a14c";
    crypttabExtraOpts = ["tpm2-device=auto" "tpm2-measure-pcr=yes"];
  };

  boot.initrd.luks.devices."luks-e1906a9e-c934-4352-bfea-02620b6abd80" = {
    device = "/dev/disk/by-uuid/e1906a9e-c934-4352-bfea-02620b6abd80";
    crypttabExtraOpts = ["tpm2-device=auto"];
  };

  # TPM2 kernel modules are merged into boot.initrd.availableKernelModules
  # above.

  # ─── Hibernation: NOT enabled, because it cannot work on this layout ───
  # The LUKS swap partition (luks-e1906…) is 8.8 GiB against 30.6 GiB of RAM,
  # so the kernel refuses to hibernate — swap must be >= RAM. `boot.resumeDevice`
  # used to be set here, which made the config read as if hibernation worked
  # when `systemctl hibernate` would always bail out.
  #
  # To enable it for real, the swap partition has to be recreated at >= 31 GiB.
  # That is destructive and offline work, not a config change:
  #   1. Boot installation media and unlock the disk.
  #   2. `swapoff`, delete and recreate the partition >= 31 GiB, re-`luksFormat`,
  #      `mkswap`, and update the UUIDs in hardware-configuration.nix and in
  #      boot.initrd.luks.devices above.
  #   3. Re-add: boot.resumeDevice = "/dev/mapper/luks-<new-uuid>";
  #      (A raw swap partition needs no resume_offset, unlike a btrfs swapfile.)
  #   4. Then `suspend-then-hibernate` becomes worthwhile for long sleeps —
  #      9h of s2idle costs a large fraction of this 41 Wh battery.
  # Verify with `swapon --show` and `free -h` before trusting any of it.

  # TPM2 userspace support
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
  };

  # SD card reader is merged into boot.kernelModules above.

  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        mesa
      ];
    };

    enableRedistributableFirmware = true;

    # Bluetooth (Intel AX200)
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Enable = "Source,Sink,Media,Socket";
          Experimental = true;
        };
      };
    };

    # ThinkPad specific
    trackpoint.enable = true;
    firmware = with pkgs; [linux-firmware sof-firmware wireless-regdb];

    # Ambient light sensor (if present)
    sensor.iio.enable = true;
  };

  # ─── BTRFS maintenance ───
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = ["/"];
  };

  # ─── ThinkPad power management ───
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.logind = {
    settings.Login = {
      # "ignore", not "lock" (and not "suspend"): the shell's lock plugin
      # does not listen to logind's Lock()/LockedHint, so a logind lock would
      # be a no-op — locking on lid close is the Hyprland binding's job
      # (lid-close script). On AC the machine stays awake: lock only, no
      # suspend. Suspend on battery stays logind's.
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      # "lock", not "suspend". A black screen invites a power-button tap, and
      # with suspend that put the machine straight back to sleep mid-diagnosis
      # (2026-07-29 08:32). Locking is idempotent and harmless when already
      # locked; long-press still powers off.
      HandlePowerKey = "lock";
      HandlePowerKeyLongPress = "poweroff";
    };
  };

  # ─── Battery-aware power profiles ───
  # Auto-select a power profile based on AC/battery state — at boot and on
  # every plug/unplug. Mirrors Omarchy's powerprofiles-init: balanced on AC,
  # power-saver on battery. (The `toggle-power-profile` script still lets you
  # override manually; the next plug/unplug re-applies the automatic choice.)
  systemd.services.power-profile-auto = {
    description = "Select power profile based on AC/battery state";
    # Hang this off the daemon, not off a target. power-profiles-daemon.service
    # ships `After=multi-user.target`, and a target is implicitly ordered after
    # everything in its Wants= — so `wantedBy = ["multi-user.target"]` here plus
    # `after = ppd` closes an ordering cycle and switch-to-configuration aborts
    # with status 4. Services get no such implicit ordering, so binding to the
    # daemon is safe and also runs the selector every time the daemon restarts.
    wantedBy = ["power-profiles-daemon.service"];
    partOf = ["power-profiles-daemon.service"];
    after = ["power-profiles-daemon.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "power-profile-auto" ''
        set -euo pipefail
        on_ac=0
        for dir in /sys/class/power_supply/*; do
          [ -r "$dir/type" ] || continue
          # USB counts as AC: on this machine the charger is USB-C PD, and a
          # PD supply enumerates as type=USB, not type=Mains. Matching only
          # Mains left the profile stuck on power-saver while charging.
          case "$(cat "$dir/type")" in
            Mains | USB) ;;
            *) continue ;;
          esac
          [ -r "$dir/online" ] || continue
          [ "$(cat "$dir/online")" = "1" ] && on_ac=1
        done
        if [ "$on_ac" = "1" ]; then
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced || true
        else
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver || true
        fi
      '';
    };
  };

  # Re-run the selector whenever a supply changes state. Filtering on type
  # avoids firing on the battery's frequent capacity uevents; both Mains and
  # USB are matched because the charger here is USB-C PD (see the type check
  # in power-profile-auto above).
  #
  # `systemctl start` rather than `systemd-run --unit=<fixed-name>`: upstream
  # Omarchy used a fixed transient unit name and had to drop it (749a8c04),
  # because resume fires several power_supply events at once and every one
  # after the first failed with "unit already loaded". Starting a persistent
  # unit is idempotent — concurrent starts coalesce into the running job.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl start --no-block power-profile-auto.service"
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="${pkgs.systemd}/bin/systemctl start --no-block power-profile-auto.service"
  '';

  # ─── Keyboard ───
  services.xserver.xkb = {
    layout = "us";
    options = "compose:caps";
  };

  # NFS /mnt/tubeinas, rootless Docker and the home Snapper config live in
  # the shared networking/dev/snapper aspects (host-agnostic workstation
  # policy, both hosts need them). Storage/swap hardware facts stay here.

  system.stateVersion = "25.05";
}
