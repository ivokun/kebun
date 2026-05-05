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
    crypttabExtraOpts = [ "tpm2-device=auto" "tpm2-measure-pcr=yes" ];
  };

  boot.initrd.luks.devices."luks-e1906a9e-c934-4352-bfea-02620b6abd80" = {
    device = "/dev/disk/by-uuid/e1906a9e-c934-4352-bfea-02620b6abd80";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };

  # TPM2 kernel modules for initrd
  boot.initrd.availableKernelModules = [ "tpm_crb" "tpm_tis" ];

  # TPM2 userspace support
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
  };

  # SD card reader (Realtek RTS525A)
  boot.kernelModules = [ "rtsx_pci" ];

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
    firmware = with pkgs; [ linux-firmware sof-firmware wireless-regdb ];

    # Ambient light sensor (if present)
    sensor.iio.enable = true;
  };

  # ─── BTRFS maintenance ───
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };

  # ─── ThinkPad power management ───
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.logind = {
    lidSwitch = "suspend";
    lidSwitchExternalPower = "suspend";
    lidSwitchDocked = "ignore";
  };

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

  system.stateVersion = "25.05";
}
