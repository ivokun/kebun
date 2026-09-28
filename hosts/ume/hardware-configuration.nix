# ⚠️ PRE-INSTALL HARDWARE SNAPSHOT — ume (current ivokun-htpc disk layout) ⚠️
#
# This file records the CURRENT disk layout of the target machine BEFORE a
# kebun install. If (re)partitioning during installation changes UUIDs,
# subvolume names, the mapper name or the swapfile location, REGENERATE this
# file with `nixos-generate-config` (or diff by hand) and re-check:
#
#   - ESP UUID (boot, vfat)
#   - LUKS2 UUID + the mapper name it unlocks as ("root" here)
#   - Btrfs UUID + subvolumes (@, @home, @log)
#   - Btrfs swapfile /swap/swapfile
#   - the ext4 media disk /dev/sda → /mnt/entertainments
#
# /dev/sdb is a REMOVABLE NTFS thumbdrive ("thumbdisk") — deliberately NOT
# configured anywhere in kebun. Do not add it here.
{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Initrd modules: NVMe boot disk, SATA (the /dev/sda media disk), USB and
  # the Btrfs tools needed for the subvol mounts.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usb_storage"
    "usbhid"
    "uas"
    "sd_mod"
    "btrfs"
    # TPM2 (auto-unlock)
    "tpm_crb"
    "tpm_tis"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # ─── Primary disk: /dev/nvme0n1 (LUKS2 → Btrfs) ───
  # Current mapper name is "root"; it must stay in sync with
  # boot.initrd.luks.devices in default.nix.
  # Inner Btrfs filesystem UUID: 1ba0592d-e0e2-44dc-a8cb-6dec12f4b417.

  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@" "compress=zstd:3"];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@home" "compress=zstd:3"];
  };

  fileSystems."/var/log" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@log" "compress=zstd:3"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/17FE-CA36";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # Existing Btrfs swapfile inside the @ root subvolume (there is no separate
  # /swap mount), byte-for-byte as found. The path alone cannot record its
  # required NODATACOW/preallocated extent properties; verify those with the
  # read-only gate in INSTALL-UME.md after any install-time disk change.
  # Hibernation is NOT claimed and no boot.resumeDevice is set — a Btrfs
  # swapfile hibernation target also needs a verified resume_offset, which is
  # deliberately deferred.
  swapDevices = [{device = "/swap/swapfile";}];

  # ─── Secondary disk: /dev/sda, ext4 media disk ───
  # Mounted non-blockingly so the machine boots fine when it is absent.
  fileSystems."/mnt/entertainments" = {
    device = "/dev/disk/by-uuid/5a56e7ae-9a37-49c2-9a98-728c5500a08d";
    fsType = "ext4";
    options = [
      "noatime"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.device-timeout=5s"
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
