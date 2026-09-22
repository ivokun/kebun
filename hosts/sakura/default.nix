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
  boot.initrd.kernelModules = ["amdgpu"];
  services.xserver.videoDrivers = ["amdgpu"];

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

  # TPM2 kernel modules for initrd
  boot.initrd.availableKernelModules = ["tpm_crb" "tpm_tis"];

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

  # SD card reader (Realtek RTS525A)
  boot.kernelModules = ["rtsx_pci"];

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

  # ─── NFS Mount (tubeinas via Tailscale) ───
  # Using automount to avoid boot hang when not on the Tailscale network
  fileSystems."/mnt/tubeinas" = {
    device = "192.168.100.29:/mnt/tank/ivokun";
    fsType = "nfs";
    options = [
      "vers=4"
      "rw"
      "nosuid"
      "nodev"
      "noexec"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=tailscaled.service"
      "x-systemd.after=tailscaled.service"
      "noauto"
      "_netdev"
    ];
  };

  # ─── Docker ───
  # Rootless Docker preserves the lazydocker workflow without granting the
  # desktop user root-equivalent access to the system daemon socket.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # ─── Keyboard ───
  services.xserver.xkb = {
    layout = "us";
    options = "compose:caps";
  };

  # ─── Btrfs Snapshots (home only) ───
  services.snapper.configs = {
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = ["ivokun"];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 10;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 12;
    };
  };

  # systemd-tmpfiles `v` is not sufficient here: it only creates a Btrfs
  # subvolume when `/` itself is a subvolume, while sakura deliberately mounts
  # Btrfs's top level as `/`. Safely migrate the empty regular directory that
  # the old tmpfiles `d` rule may have left behind, but never delete contents.
  # Snapper is held back if the path is non-empty or otherwise unexpected.
  systemd.services.home-snapshots-subvolume = {
    description = "Provision the /home Snapper subvolume";
    wantedBy = ["multi-user.target"];
    requiredBy = [
      "snapperd.service"
      "snapper-timeline.service"
      "snapper-cleanup.service"
    ];
    before = [
      "snapperd.service"
      "snapper-timeline.service"
      "snapper-cleanup.service"
    ];
    unitConfig.RequiresMountsFor = "/home";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      target=/home/.snapshots

      if ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$target" >/dev/null 2>&1; then
        ${pkgs.coreutils}/bin/chown ivokun:users "$target"
        ${pkgs.coreutils}/bin/chmod 0750 "$target"
        exit 0
      fi

      if [ -e "$target" ]; then
        if [ ! -d "$target" ] || [ -n "$(${pkgs.findutils}/bin/find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
          echo "$target exists but is not an empty Btrfs subvolume; refusing to replace it" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/rmdir -- "$target"
      fi

      ${pkgs.btrfs-progs}/bin/btrfs subvolume create "$target"
      ${pkgs.coreutils}/bin/chown ivokun:users "$target"
      ${pkgs.coreutils}/bin/chmod 0750 "$target"
    '';
  };

  system.stateVersion = "25.05";
}
