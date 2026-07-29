{
  config,
  lib,
  pkgs,
  inputs,
  hostname,
  username,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = hostname;

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
    lidSwitch = "suspend";
    lidSwitchExternalPower = "suspend";
    lidSwitchDocked = "ignore";
    # "lock", not "suspend". A black screen invites a power-button tap, and
    # with suspend that put the machine straight back to sleep mid-diagnosis
    # (2026-07-29 08:32). Locking is idempotent and harmless when already
    # locked; long-press still powers off.
    powerKey = "lock";
    powerKeyLongPress = "poweroff";
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
          [ "$(cat "$dir/type")" = "Mains" ] || continue
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

  # Re-run the selector whenever the AC adapter changes state. Filtering on
  # type=Mains avoids firing on the battery's frequent capacity uevents.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl start --no-block power-profile-auto.service"
  '';

  # ─── NFS Mount (tubeinas via Tailscale) ───
  # Using automount to avoid boot hang when not on the Tailscale network
  fileSystems."/mnt/tubeinas" = {
    device = "192.168.100.29:/mnt/tank/ivokun";
    fsType = "nfs";
    options = ["vers=4" "rw" "x-systemd.automount" "x-systemd.idle-timeout=600" "noauto" "_netdev"];
  };

  # ─── Docker ───
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
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

  # ─── Btrfs Snapshots (home only) ───
  # NOTE: /home/.snapshots must be a BTRFS subvolume, not a regular directory.
  # Create it manually before first rebuild:
  #   sudo btrfs subvolume create /home/.snapshots
  # This tmpfiles rule only ensures permissions after the subvolume exists.
  systemd.tmpfiles.rules = [
    "d /home/.snapshots 0750 ivokun users -"
  ];

  system.stateVersion = "25.05";
}
