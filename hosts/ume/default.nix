# Host: ume — ASRock B550M-ITX/ac desktop, Ryzen 9 5900X, RX 9060 XT (Navi 44).
# Pre-install representation of the current ivokun-htpc hardware: the disk
# facts live in hardware-configuration.nix (snapshot of the CURRENT layout —
# regenerate it if installation repartitions; see the banner there).
# Shared workstation policy comes from the aspects wired in
# modules/aspects.nix (networking NFS, dev Docker, snapper home timeline);
# only machine-specific facts live here.
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  # ─── AMD Radeon RX 9060 XT / Navi 44 (discrete dGPU, amdgpu) ───
  services.xserver.videoDrivers = ["amdgpu"];
  hardware.amdgpu.initrd.enable = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [mesa];
    # Steam games link 32-bit GL/Vulkan; enable32Bit adds the i686 mesa
    # driver set automatically (passing 64-bit pkgs.mesa here would collide
    # with it in buildEnv).
    enable32Bit = true;
  };

  # ─── Machine-specific kernel wiring (B550 / Vermeer desktop) ───
  # vhost_vsock is required by claude-desktop's Cowork VM; btusb serves the
  # board's Intel AC 3168 Bluetooth controller.
  boot.kernelModules = ["amdgpu" "kvm-amd" "btusb" "vhost_vsock"];

  # ─── LUKS TPM2 auto-unlock ───
  # systemd initrd so crypttab supports tpm2-device=auto. The mapper name
  # ("root") must match hardware-configuration.nix; if TPM2 policy breaks
  # (e.g. firmware changes PCR 7) the kernel falls back to the passphrase
  # prompt. After the login password is separately enrolled with
  # `cryptsetup luksAddKey`, desktop.nix's PAM hook can reuse it for devices
  # listed in boot.initrd.luks.devices.
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-uuid/fdfeaf01-6060-473f-9d01-dfd685d2e2fd";
    crypttabExtraOpts = ["tpm2-device=auto" "tpm2-measure-pcr=yes"];
  };

  # TPM2 userspace support
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
  };

  # ─── Firmware (AMD CPU microcode set in hardware-configuration.nix) ───
  hardware = {
    enableRedistributableFirmware = true;

    # Bluetooth (Intel AC 3168)
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
  };

  # ─── BTRFS maintenance ───
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = ["/"];
  };

  # ─── Desktop power management ───
  # No lid/battery behavior: this is a desktop host (kebun.host.isLaptop =
  # false keeps Home Manager from emitting laptop-only pieces).
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.logind.settings.Login = {
    # Same rationale as sakura: "lock", not "suspend" — a black screen
    # invites a stray power-button tap; long-press still powers off.
    HandlePowerKey = "lock";
    HandlePowerKeyLongPress = "poweroff";
  };

  # ─── Flatpak ───
  services.flatpak.enable = true;

  # ─── Steam ───
  programs.steam.enable = true;

  # ─── Xpadneo (Xbox controllers over Bluetooth) ───
  hardware.xpadneo.enable = true;

  # ─── LAN Mouse ───
  # The certificate and peer authorization remain private runtime state under
  # ~/.config/lan-mouse; restore them separately instead of putting the PEM in
  # the Nix store.
  environment.systemPackages = [pkgs.lan-mouse];
  systemd.user.services.lan-mouse = {
    description = "LAN Mouse";
    after = ["graphical-session.target"];
    bindsTo = ["graphical-session.target"];
    wantedBy = ["graphical-session.target"];
    serviceConfig = {
      ExecStart = "${pkgs.lan-mouse}/bin/lan-mouse --capture-backend layer-shell daemon";
      Restart = "on-failure";
    };
  };

  # LAN Mouse listens on UDP 4242. Keep remote-control traffic off arbitrary
  # Wi-Fi networks; ume is wired in normal operation.
  networking.firewall.interfaces."en+".allowedUDPPorts = [4242];

  # ─── Keyboard ───
  services.xserver.xkb = {
    layout = "us";
    options = "compose:caps";
  };

  # ─── Kebun host surface (consumed by Home Manager via osConfig) ───
  kebun.host = {
    isLaptop = false;
    greeterLayout = "us";
    monitorsLua = ''
      -- Kebun monitor layout — ume's current panels: DP-1 Lenovo P27Q-40
      -- (2560x1440) and DP-2 LG UltraFine (3840x2160). Matches the
      -- configuration the machine runs today: a generic preferred/auto rule
      -- at 1.25. Narrow to per-output rules once verified on real hardware.
      hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.25 })
    '';
  };

  system.stateVersion = "25.05";
}
