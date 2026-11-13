# Hardware layout — sakura (ThinkPad X13 Gen 1, AMD Renoir), installed
# 2026-09-04. Began as `nixos-generate-config` output; it is hand-maintained
# now, so edit it in place instead of regenerating over it. If the disk is
# ever repartitioned, reconcile every UUID below (and the LUKS devices in
# default.nix) against the running machine before switching:
#
#   - ESP UUID (boot, vfat) ............ 7AF5-F308
#   - LUKS2 root container ............. 5525027e-…-3ab692f4a14c
#     (Btrfs top level mounted as `/`; subvolumes home, nix)
#   - LUKS2 swap container ............. e1906a9e-…-02620b6abd80
{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Initrd modules: NVMe boot disk, USB (incl. the Renesas controller), the
  # Realtek SD reader, Btrfs, and the TPM2 drivers for LUKS auto-unlock.
  boot.initrd.availableKernelModules = [
    "nvme"
    "ehci_pci"
    "xhci_pci_renesas"
    "xhci_pci"
    "ahci"
    "usb_storage"
    "usbhid"
    "uas"
    "sd_mod"
    "rtsx_pci_sdmmc"
    "btrfs"
    # TPM2 (auto-unlock)
    "tpm_crb"
    "tpm_tis"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # ─── Primary disk: LUKS2 → Btrfs ───
  # The mapper name must stay in sync with boot.initrd.luks.devices in
  # default.nix, which owns the LUKS declarations.

  fileSystems."/" = {
    device = "/dev/mapper/luks-5525027e-a087-470e-a530-3ab692f4a14c";
    fsType = "btrfs";
  };

  fileSystems."/home" = {
    device = "/dev/mapper/luks-5525027e-a087-470e-a530-3ab692f4a14c";
    fsType = "btrfs";
    options = ["subvol=home"];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/luks-5525027e-a087-470e-a530-3ab692f4a14c";
    fsType = "btrfs";
    options = ["subvol=nix"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/7AF5-F308";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # Dedicated LUKS swap partition (8.8 GiB < RAM, so no hibernation — see
  # default.nix).
  swapDevices = [
    {device = "/dev/mapper/luks-e1906a9e-c934-4352-bfea-02620b6abd80";}
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
