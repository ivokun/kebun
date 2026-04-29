# NixOS + Flakes + Omarchy Replication Plan

## TL;DR

This plan guides you through installing NixOS with Flakes on your Lenovo ThinkPad X13 Gen 1 (AMD Ryzen 5 PRO 4650U + Renoir integrated graphics), using BTRFS + LUKS encryption, and replicating your current Arch/Omarchy Hyprland desktop using the `kebun` flake repository. The result is a declarative, reproducible system where `nh os switch .` replaces `omarchy-update`, and all desktop configuration—Hyprland, Waybar, terminals, shell, theme, Japanese input—lives in version-controlled Nix code under `hosts/sakura/` and `home/`.

## Context

- **Original Request**: Install NixOS with Flakes and replicate Omarchy desktop
- **Hardware**:
  - Laptop: Lenovo ThinkPad X13 Gen 1 (20UGS2Q500)
  - CPU: AMD Ryzen 5 PRO 4650U (6-core/12-thread)
  - GPU: AMD Renoir (Radeon Vega Series / Radeon Vega Mobile Series) — amdgpu driver
  - RAM: 32GB
  - Boot: UEFI
  - NVMe: 238.5GB Samsung MZALQ256HAJD-000L1 (OS drive, `/dev/nvme0n1`)
  - USB: HP v210w 7.5GB (Omarchy live USB, `/dev/sda`)
  - Display: eDP-1, 1920x1080@60Hz (scale 1.5, laptop internal)
  - Network: Wired (enp2s0f0) + WiFi (wlan0, Intel AX200) + Tailscale + Docker
  - Bluetooth: Intel AX200 (hci0)
- **Key Decisions**:
  1. Minimal replacement for omarchy scripts (not full 145-command replication)
  2. Multi-machine flake structure (`hosts/sakura/`, extensible)
  3. NixOS unstable channel
  4. zsh + oh-my-zsh (matching current Arch setup)
  5. BTRFS + LUKS encryption (matching current Arch: `@root`, `@home`, `@log`, `@pkg`, `@swap`)
  6. Hostname: `sakura` (fits the "kebun" garden theme — kebun = garden, sakura = cherry blossom)
  7. systemd-boot (cleaner for UEFI + BTRFS + LUKS)
  8. Hyprland via UWSM (matching current Arch setup)
  9. Rose Pine Dawn theme across all apps
  10. nh for rebuilds (`nh os switch .`)

---

## Phase 0: Pre-Installation Preparation

### Step 0.1: Backup Current System

Back up everything you need from the Arch installation before wiping the NVMe drive.

**What to back up:**

| Category | Path | Notes |
|----------|------|-------|
| SSH keys | `~/.ssh/` | Private keys, config, known_hosts |
| GPG keys | `~/.gnupg/` | Export with `gpg --export-secret-keys` |
| Git config | `~/.gitconfig` | Copy directly |
| Shell history | `~/.local/share/atuin/` | Atuin history DB |
| Browser data | `~/.config/brave/` | Bookmarks, extensions, passwords (or use Brave sync) |
| Obsidian vaults | Check vault paths | Copy entire vault directories |
| Signal data | `~/.config/Signal/` | Encrypted, can re-link |
| Neovim config | `~/.config/nvim/` | LazyVim setup |
| Starship config | `~/.config/starship.toml` | Copy directly |
| tmux config | `~/.config/tmux/tmux.conf` | Copy directly |
| Custom scripts | `~/.local/bin/` | Any personal scripts |
| Waybar/Hyprland | `~/.config/{waybar,hypr,mako}/` | Reference only — will be in Nix |
| Wallpaper | `~/.config/omarchy/current/background` | Copy the wallpaper image |
| NFS mount config | `/etc/fstab` NFS line | Note the tubeinas mount details |
| Docker volumes | `docker volume ls` | Note volumes to recreate |

**Commands:**

```bash
# Create backup directory on a USB drive or network storage
# (NOT the NVMe we're wiping)
mkdir -p /tmp/arch-backup-$(date +%Y%m%d)
BACKUP=/tmp/arch-backup-$(date +%Y%m%d)

# Dotfiles
cp -a ~/.ssh "$BACKUP/ssh"
cp -a ~/.gnupg "$BACKUP/gnupg" 2>/dev/null
cp ~/.gitconfig "$BACKUP/gitconfig"
cp -a ~/.config/starship.toml "$BACKUP/starship.toml"
cp -a ~/.config/tmux "$BACKUP/tmux"
cp -a ~/.config/nvim "$BACKUP/nvim"
cp -a ~/.config/mako "$BACKUP/mako"
cp -a ~/.local/share/atuin "$BACKUP/atuin"
cp -a ~/.local/bin "$BACKUP/local-bin" 2>/dev/null

# Atuin key (for re-linking)
cp ~/.local/share/atuin/key "$BACKUP/atuin-key"
cp ~/.local/share/atuin/session "$BACKUP/atuin-session" 2>/dev/null

# Wallpaper
cp ~/.config/omarchy/current/background "$BACKUP/wallpaper"

# Record installed packages list (for reference)
pacman -Qqe > "$BACKUP/pkglist.txt"
yay -Qm > "$BACKUP/aur-list.txt" 2>/dev/null

# Record fstab for NFS mount
cp /etc/fstab "$BACKUP/fstab"

# Note the LUKS UUID for reference
blkid /dev/nvme0n1p2 > "$BACKUP/blkid-nvme.txt"
```

### Step 0.2: Create NixOS USB

```bash
# Download NixOS minimal ISO (unstable/latest)
# https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso

# Write to USB (replace sdX with your USB device)
lsblk  # Identify the USB device
sudo dd if=nixos-minimal-25.05beta-*.x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### Step 0.3: Verify Boot from USB

1. Boot from USB, select the NixOS installer
2. Confirm you get a root shell
3. Test network: `ping google.com`
4. If WiFi needed: `iwctl` then `station wlan0 connect "YOUR_SSID"`

---

## Phase 1: NixOS Base Installation

### Step 1.1: Boot and Network

```bash
# Set console keymap if needed
loadkeys us

# Connect to WiFi if no wired connection
iwctl
# station wlan0 connect "YOUR_SSID"
# exit

# Verify connectivity
ping -c 3 google.com

# Optional: SSH from another machine for easier copy-paste
systemctl start sshd
passwd  # Set temp root password for SSH
ip addr show  # Note the IP
# From another machine: ssh root@<ip>
```

### Step 1.2: Partition Disk (LUKS + BTRFS)

**Partition Layout:**

| Device | Partition | Size | Type | Mount |
|--------|-----------|------|------|------|
| `/dev/nvme0n1` | `p1` (ESP) | 2 GiB | EFI System | `/boot` |
| `/dev/nvme0n1` | `p2` (LUKS) | ~236 GiB | Linux filesystem | LUKS → BTRFS |

**BTRFS Subvolumes inside LUKS:**

| Subvolume | Mount Point |
|------------|-------------|
| `@` | `/` |
| `@home` | `/home` |
| `@log` | `/var/log` |
| `@pkg` | `/var/cache/pacman/pkg` (or `/var/cache` on NixOS) |
| `@swap` | `/swap` |

```bash
# Wipe the disk and create partitions
# WARNING: This destroys all data on /dev/nvme0n1

# Partition with gdisk
gdisk /dev/nvme0n1
# Inside gdisk:
#   o                    (create new GPT partition table)
#   n → 1 → default → +2G → EF00  (EFI System Partition)
#   n → 2 → default → default → 8309  (Linux LUKS)
#   w                    (write and exit)

# Format the ESP
mkfs.vfat -F 32 -n EFI /dev/nvme0n1p1

# Create LUKS encrypted partition
cryptsetup luksFormat /dev/nvme0n1p2
# Enter your passphrase (choose a strong one — this protects your entire disk)

# Open the LUKS container
cryptsetup open /dev/nvme0n1p2 root

# Create BTRFS filesystem on the LUKS container
mkfs.btrfs -L nixos /dev/mapper/root

# Create subvolumes
mount /dev/mapper/root /mnt

btrfs subvolume create /mnt/@root
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@swap

# Unmount to mount with subvolumes
umount /mnt

# Mount the root subvolume with compression
mount -o compress=zstd:3,ssd,noatime,subvol=@root /dev/mapper/root /mnt

# Create mount points and mount subvolumes
mkdir -p /mnt/{boot,home,var/log,nix,swap}

mount -o compress=zstd:3,ssd,noatime,subvol=@home /dev/mapper/root /mnt/home
mount -o compress=zstd:3,ssd,noatime,subvol=@log /dev/mapper/root /mnt/var/log
mount -o compress=zstd:3,ssd,noatime,subvol=@pkg /dev/mapper/root /mnt/var/cache
mount -o subvol=@swap /dev/mapper/root /mnt/swap

# Mount the ESP
mount /dev/nvme0n1p1 /mnt/boot

# Create swapfile (32GB, matching current setup)
btrfs filesystem mkswapfile --size 32g /mnt/swap/swapfile
```

### Step 1.3: Generate Initial Config

```bash
# Generate NixOS configuration
nixos-generate-config --root /mnt

# The generated files are at:
# /mnt/etc/nixos/configuration.nix
# /mnt/etc/nixos/hardware-configuration.nix
```

Edit `/mnt/etc/nixos/configuration.nix` to add minimal boot config before installing:

```nix
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable flakes immediately
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "sakura";

  # Set your timezone
  time.timeZone = "Asia/Tokyo";

  # Basic user for initial setup
  users.users.ivokun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # AMD GPU
  services.xserver.videoDrivers = [ "amdgpu" ];

  system.stateVersion = "25.05";
}
```

Check `/mnt/etc/nixos/hardware-configuration.nix` — it should already have the correct UUIDs and mount options. Verify it includes the `neededForBoot` flags for `/var/log` and the LUKS device.

### Step 1.4: Install

```bash
# Install NixOS
nixos-install

# Set root password when prompted
# Then set user password
nixos-install --root /mnt  # This will prompt for root password

# Set ivokun password
echo "ivokun:YOUR_PASSWORD" | chroot /mnt chpasswd

# Reboot
reboot
```

After reboot, you should be able to log in as `ivokun` at the console.

---

## Phase 2: Flake Repository Setup

### Step 2.1: Initial flake.nix Structure

```nix
{
  description = "Kebun — NixOS garden configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nh — Nix Helper for rebuilds
    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Walker app launcher
    walker = {
      url = "github:abenz957/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rose Pine theme for Nix
    rose-pine = {
      url = "github:rose-pine/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-index database for command-not-found
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    hyprland,
    nh,
    walker,
    rose-pine,
    nix-index-database,
    ...
  } @ inputs: let
    systems = {
      sakura = {
        system = "x86_64-linux";
        hostname = "sakura";
        username = "ivokun";
      };
    };

    sharedModules = [
      ./hosts/common/core.nix
      ./hosts/common/desktop.nix
      ./hosts/common/dev.nix
      ./hosts/common/networking.nix
      ./hosts/common/users.nix
      nix-index-database.nixosModules.nix-index
    ];

    mkHomeManagerModules = {username, hostname, ...}: [
      {
        home-manager.users.${username} = {
          imports = [
            ./home/common.nix
            ./home/sakura.nix
            ./home/features/hyprland.nix
            ./home/features/waybar.nix
            ./home/features/terminals.nix
            ./home/features/shell.nix
            ./home/features/editors.nix
            ./home/features/theme-rose-pine.nix
            ./home/features/fcitx5.nix
            rose-pine.homeManagerModules.rose-pine
          ];
        };
      }
    ];

    mkSystem = name: cfg: let
      inherit (cfg) system hostname username;
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;} // cfg;
        modules =
          sharedModules
          ++ [
            ./hosts/${hostname}
            home-manager.nixosModules.home-manager
            {
              home-manager.extraSpecialArgs = {inherit inputs;} // cfg;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
            }
          ]
          ++ mkHomeManagerModules cfg;
      };
  in {
    nixosConfigurations = nixpkgs.lib.mapAttrs mkSystem systems;

    # Allow `nix fmt` to work
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
  };
}
```

### Step 2.2: Directory Structure

```
kebun/
├── flake.nix
├── flake.lock
├── hosts/
│   ├── common/
│   │   ├── core.nix
│   │   ├── desktop.nix
│   │   ├── dev.nix
│   │   ├── networking.nix
│   │   └── users.nix
│   └── sakura/
│       ├── default.nix
│       └── hardware-configuration.nix
├── home/
│   ├── common.nix
│   ├── sakura.nix
│   └── features/
│       ├── hyprland.nix
│       ├── waybar.nix
│       ├── terminals.nix
│       ├── shell.nix
│       ├── editors.nix
│       ├── theme-rose-pine.nix
│       └── fcitx5.nix
├── modules/
│   └── theme.nix
├── packages/
│   └── scripts/
│       ├── screenshot.sh
│       ├── volume-toggle.sh
│       ├── brightness-toggle.sh
│       └── lock-screen.sh
├── themes/
│   └── rose-pine/
│       ├── colors.nix
│       ├── waybar.css
│       └── hyprland.conf
└── wallpapers/
```

### Step 2.3: Clone and Push Initial Config

After the initial NixOS install boots to a console:

```bash
# Log in as ivokun

# Install git
sudo nix-shell -p git

# Create the kebun directory structure
mkdir -p ~/Documents/dev/kebun
cd ~/Documents/dev/kebun

# Initialize git
git init

# Create directory structure
mkdir -p hosts/{common,sakura}
mkdir -p home/features
mkdir -p modules
mkdir -p packages/scripts
mkdir -p themes/rose-pine
mkdir -p wallpapers

# Copy hardware-configuration from the installed system
cp /etc/nixos/hardware-configuration.nix hosts/sakura/hardware-configuration.nix

# After writing all the config files below, commit and test:
git add .
git commit -m "Initial kebun flake structure"

# Push to GitHub (create repo first)
# gh repo create ivokun/kebun --private --source=. --push

# Apply the flake
cd ~/Documents/dev/kebun
sudo nixos-rebuild switch --flake .#sakura

# After confirming it works, switch to using nh:
# nh os switch .
```

---

## Phase 3: Core NixOS Configuration

### Step 3.1: hosts/common/core.nix

```nix
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

    # LUKS — the device UUID will be in hardware-configuration.nix
    # but we need to ensure initrd has the right modules
    initrd = {
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "uas" "sd_mod" "btrfs"];
      kernelModules = ["amdgpu" "kvm-amd"];
    };

    kernelModules = ["amdgpu" "kvm-amd" "btusb" "thinkpad_acpi"];
    extraModulePackages = [];

    # Btrfs mount options are set in hardware-configuration.nix subvol mounts
    # but we ensure the root mount has the right options
    supportedFilesystems = ["btrfs" "vfat" "exfat" "nfs"];

    # Kernel parameters for LUKS + BTRFS + AMD
    kernelParams = [
      "amd_iommu=on"
      "amdgpu.sg_display=0"
      "rtc_cmos.use_acpi_alarm=1"
    ];
  };

  # ─── LUKS ───
  # This is generated by nixos-generate-config but we ensure it's correct
  # The actual config goes in hosts/sakura/hardware-configuration.nix

  # ─── Filesystems ───
  # Defined in hardware-configuration.nix, but we can set options here
  fileSystems = {
    "/".options = ["compress=zstd:3" "noatime" "ssd"];
    "/home".options = ["compress=zstd:3" "noatime" "ssd"];
    "/var/cache".options = ["compress=zstd:3" "noatime" "ssd"];
    "/var/log".options = ["compress=zstd:3" "noatime" "ssd"];
  };

  # ─── Swap ───
  # Primary: zram (compressed in-memory swap)
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
  # Fallback: swapfile on BTRFS subvolume
  swapDevices = [{device = "/swap/swapfile";}];

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
    font = "Lat2-Terminus16";
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
        "cache.nixos.org-1:6NCHdD59x4g^{hash}="
        "hyprland.cachix.org-1:a7pgxQMzO+MR^{hash}="
      ];
      trusted-users = ["root" "@wheel"];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    # Track the flake registry to the nixpkgs input
    registry.nixpkgs.flake = inputs.nixpkgs;
  };

  nixpkgs.config.allowUnfree = true;

  # ─── Networking ───
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [22]; # SSH
    };
    # Hostname is set per-host in hosts/sakura/default.nix
  };

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

  # ─── Auto Upgrade ───
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = ["--update-input" "nixpkgs"];
  };

  # ─── System Packages ───
  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    pciutils
    usbutils
    lm_sensors
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data were taken.
  system.stateVersion = "25.05";
}
```

### Step 3.2: hosts/common/users.nix

```nix
{
  config,
  pkgs,
  username,
  ...
}: {
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "docker"
      "input"
      "storage"
    ];
    shell = pkgs.zsh;
    # Initial password — change after first login with `passwd`
    initialPassword = "changeme";
  };

  programs.zsh.enable = true;

  # Elevate wheel group to trusted-users for nix
  nix.settings.trusted-users = ["root" "@wheel"];
}
```

### Step 3.3: hosts/sakura/default.nix

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  system,
  hostname,
  username,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = hostname; # "sakura"

  # ─── AMD APU (Renoir / Ryzen 5 PRO 4650U) ───
  boot.initrd.kernelModules = ["amdgpu"];
  services.xserver.videoDrivers = ["amdgpu"];

  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        mesa
        amdvlk
      ];
    };

    enableRedistributableFirmware = true;

    # Bluetooth (Intel AX200)
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # ThinkPad specific
    firmware = [pkgs.linux-firmware];
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
  fileSystems."/mnt/tubeinas" = {
    device = "192.168.100.29:/mnt/tank/ivokun";
    fsType = "nfs";
    options = ["vers=4" "rw" "_netdev"];
  };

  # ─── Docker ───
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  # ─── Tailscale ───
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # ─── ExFAT support ───
  boot.supportedFilesystems = ["exfat"];

  # ─── Keyboard ───
  services.xserver.xkb = {
    layout = "us";
    options = "compose:caps";
  };

  # ─── Fingerprint reader (ThinkPad X13 Gen 1 may have one) ───
  # services.fprintd.enable = true;

  system.stateVersion = "25.05";
}
```

### Step 3.4: hosts/sakura/hardware-configuration.nix

This file is auto-generated by `nixos-generate-config`. After generating, copy it to this path. It will contain:

- The LUKS device mapping (`boot.initrd.luks.devices.cryptroot`)
- The filesystem UUIDs and mount options
- The swap device
- The kernel modules

**Do NOT edit this manually** — it's generated. The only change you might make is adding `neededForBoot = true;` to `/var/log` mount.

Example (your UUIDs will differ):

```nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/profiles/qemu-guest.nix")];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "uas" "sd_mod"];
  boot.initrd.kernelModules = ["dm-snapshot" "amdgpu"];
  boot.kernelModules = ["kvm-amd" "thinkpad_acpi"];
  boot.extraModulePackages = [];

  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-uuid/f03e6c37-e0bb-4263-8c9c-2909ac11cceb";
    allowDiscards = true;
    bypassWorkqueues = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@root" "compress=zstd:3" "noatime" "ssd"];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@home" "compress=zstd:3" "noatime" "ssd"];
  };

  fileSystems."/var/log" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@log" "compress=zstd:3" "noatime" "ssd"];
    neededForBoot = true;
  };

  fileSystems."/var/cache" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@pkg" "compress=zstd:3" "noatime" "ssd"];
  };

  fileSystems."/swap" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@swap" "noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/3DC9-F5D4";
    fsType = "vfat";
  };

  swapDevices = [{device = "/swap/swapfile";}];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
```

---

## Phase 4: Desktop Environment (Hyprland Stack)

### Step 4.1: hosts/common/desktop.nix

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
  # ─── Hyprland ───
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    withUWSM = true; # Use UWSM for proper systemd integration
  };

  # ─── XDG ───
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };

  # ─── Polkit ───
  security.polkit.enable = true;
  environment.systemPackages = with pkgs; [polkit_gnome];

  # ─── Dconf (needed for many GTK apps) ───
  programs.dconf.enable = true;

  # ─── Fonts ───
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      (nerdfonts.override {fonts = ["CaskaydiaMono"];})
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
    ];

    fontconfig = {
      defaultFonts = {
        monospace = ["CaskaydiaMono Nerd Font" "Noto Sans Mono CJK JP"];
        sansSerif = ["Noto Sans CJK JP"];
        serif = ["Noto Serif CJK JP"];
      };
    };
  };

  # ─── Display-related services ───
  services = {
    # SwayOSD (on-screen display for volume/brightness)
    swayosd.enable = true;

    # GVfs for virtual filesystems ( trash, mtp, etc.)
    gvfs.enable = true;
  };

  # ─── Desktop packages (system-level) ───
  environment.systemPackages = with pkgs; [
    # Wayland essentials
    wl-clipboard
    wl-copy
    grim
    slurp
    swappy
    brightnessctl

    # Screenshots and screen recording
    hyprpicker

    # Wallpaper
    swaybg

    # Notifications
    mako

    # App launcher
    inputs.walker.packages.${pkgs.system}.walker

    # Polkit authentication agent
    polkit_gnome

    # Audio controls
    pamixer
    playerctl

    # Bluetooth
    bluez
    bluez-tools

    # File manager
    nautilus

    # Calculator
    gnome-calculator

    # Laptop power
    acpi
  ];

  # ─── Bluetooth ───
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ─── D-Bus ───
  services.dbus.enable = true;
}
```

### Step 4.2: home/features/hyprland.nix

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  # Rose Pine Dawn active border color
  activeBorderColor = "rgb(56949f)";
  inactiveBorderColor = "rgba(595959aa)";

  # Paths
  wallpaper = "${config.home.homeDirectory}/.config/omarchy/current/background";
  screenshotScript = pkgs.writeShellScriptBin "screenshot" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-copy}/bin/wl-copy
  '';
in {
  # ─── Hyprland Configuration ───
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    systemd = {
      enable = true;
      variables = ["--all"];
    };

    settings = {
      # ─── Monitors ───
      # Laptop internal display (ThinkPad X13 Gen 1 eDP-1)
      monitor = [
        "eDP-1,1920x1080@60,0x0,1.5"
        ",preferred,auto,1"
      ];

      # ─── Environment Variables ───
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "GDK_BACKEND,wayland,x11,*"
        "QT_QPA_PLATFORM,wayland;xcb"
        "QT_STYLE_OVERRIDE,kvantum"
        "SDL_VIDEODRIVER,wayland"
        "MOZ_ENABLE_WAYLAND,1"
        "ELECTRON_OZONE_PLATFORM_HINT,wayland"
        "OZONE_PLATFORM,wayland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "GDK_SCALE,1"

        # Japanese input method (fcitx5-mozc)
        "GTK_IM_MODULE,fcitx"
        "QT_IM_MODULE,fcitx"
        "XMODIFIERS,@im=fcitx"
      ];

      # ─── XWayland ───
      xwayland.force_zero_scaling = true;

      # ─── Ecosystem ───
      ecosystem.no_update_news = true;

      # ─── Input ───
      input = {
        kb_layout = "us";
        kb_options = "compose:caps";
        follow_mouse = 1;
        sensitivity = 0;
        repeat_rate = 40;
        repeat_delay = 600;
        numlock_by_default = true;

        touchpad = {
          natural_scroll = true;
          scroll_factor = 0.4;
          disable_while_typing = true;
          tap-to-click = true;
          drag_lock = false;
          middle_button_emulation = true;
        };
      };

      # ─── General ───
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = activeBorderColor;
        "col.inactive_border" = inactiveBorderColor;
        resize_on_border = false;
        allow_tearing = false;
        layout = "dwindle";
      };

      # ─── Decoration ───
      decoration = {
        rounding = 0;

        shadow = {
          enabled = true;
          range = 2;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;
          size = 2;
          passes = 2;
          special = true;
          brightness = 0.60;
          contrast = 0.75;
        };
      };

      # ─── Group ───
      group = {
        "col.border_active" = activeBorderColor;
        "col.border_inactive" = inactiveBorderColor;

        groupbar = {
          font_size = 12;
          font_family = "monospace";
          font_weight_active = "ultraheavy";
          font_weight_inactive = "normal";
          indicator_height = 0;
          indicator_gap = 5;
          height = 22;
          gaps_in = 5;
          gaps_out = 0;
          text_color = "rgb(ffffff)";
          text_color_inactive = "rgba(ffffff90)";
          "col.active" = "rgba(00000040)";
          "col.inactive" = "rgba(00000020)";
          gradients = true;
          gradient_rounding = 0;
          gradient_round_only_edges = false;
        };
      };

      # ─── Animations ───
      animations = {
        enabled = true;

        bezier = [
          "easeOutQuint,0.23,1,0.32,1"
          "easeInOutCubic,0.65,0.05,0.36,1"
          "linear,0,0,1,1"
          "almostLinear,0.5,0.5,0.75,1.0"
          "quick,0.15,0,0.1,1"
        ];

        animation = [
          "global, 1, 10, default"
          "border, 1, 5.39, easeOutQuint"
          "windows, 1, 4.79, easeOutQuint"
          "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
          "windowsOut, 1, 1.49, linear, popin 87%"
          "fadeIn, 1, 1.73, almostLinear"
          "fadeOut, 1, 1.46, almostLinear"
          "fade, 1, 3.03, quick"
          "layers, 1, 3.81, easeOutQuint"
          "layersIn, 1, 4, easeOutQuint, fade"
          "layersOut, 1, 1.5, linear, fade"
          "fadeLayersIn, 1, 1.79, almostLinear"
          "fadeLayersOut, 1, 1.39, almostLinear"
          "workspaces, 0, 0, ease"
        ];
      };

      # ─── Dwindle Layout ───
      dwindle = {
        pseudotile = true;
        preserve_split = true;
        force_split = 2;
      };

      # ─── Master Layout ───
      master.new_status = "master";

      # ─── Misc ───
      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        focus_on_activate = true;
        anr_missed_pings = 3;
        on_focus_under_fullscreen = 1;
      };

      # ─── Cursor ───
      cursor.hide_on_key_press = true;

      # ─── Window Rules ───
      windowrule = [
        # Suppress maximize events (Hyprland 0.53+)
        "suppress_event maximize, match:class .*"

        # Default slight transparency
        "opacity 0.97 0.9, match:class .*"

        # Fix XWayland dragging issues
        "no_focus on, match:class ^$, match:title ^$, match:xwayland 1, match:float 1, match:fullscreen 0, match:pin 0"

        # 1Password — no screen share, float
        "no_screen_share on, match:class ^(1[pP]assword)$"
        "tag +floating-window, match:class ^(1[pP]assword)$"

        # Bitwarden — no screen share, float
        "no_screen_share on, match:class ^(Bitwarden)$"
        "tag +floating-window, match:class ^(Bitwarden)$"

        # Browser tags
        "tag +chromium-based-browser, match:class ((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)"
        "tag +firefox-based-browser, match:class ([fF]irefox|zen|librewolf)"
        "tile on, match:tag chromium-based-browser"
        "opacity 1 0.97, match:tag chromium-based-browser"
        "opacity 1 0.97, match:tag firefox-based-browser"

        # Terminal tag
        "tag +terminal, match:class (Alacritty|kitty|com.mitchellh.ghostty)"

        # Floating windows
        "float on, match:tag floating-window"
        "center on, match:tag floating-window"
        "size 875 600, match:tag floating-window"

        # Calculator
        "float on, match:class org.gnome.Calculator"

        # Media — no transparency
        "opacity 1 1, match:class ^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$"

        # Popped windows — rounding
        "rounding 8, match:tag pop"

        # Idle inhibit on fullscreen
        "idle_inhibit fullscreen, match:class .*"
      ];

      # ─── Layer Rules ───
      layerrule = [
        "no_anim on, match:namespace walker"
      ];

      # ─── Keybindings ───
      "$terminal" = "uwsm app -- $TERMINAL";
      "$browser" = "brave";
      "$osdclient" = "swayosd-client --monitor \"$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true).name')\"";

      bindd = [
        # ─── Application Launchers ───
        "SUPER, RETURN, Terminal, exec, $terminal --dir=\"$(${pkgs.zoxide}/bin/zoxide query --interactive || pwd)\""
        "SUPER SHIFT, F, File manager, exec, uwsm app -- nautilus --new-window"
        "SUPER, B, Browser, exec, $browser"
        "SUPER SHIFT, B, Browser (private), exec, $browser --private"
        "SUPER, N, Editor, exec, uwsm app -- nvim"
        "SUPER, D, Docker, exec, uwsm app -- ${pkgs.foot}/bin/foot -e lazydocker"
        "SUPER, O, Obsidian, exec, uwsm app -- obsidian -disable-gpu --enable-wayland-ime"
        "SUPER, slash, Passwords, exec, uwsm app -- 1password"

        # ─── Menus ───
        "SUPER, SPACE, Launch apps, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        "SUPER CTRL, E, Emoji picker, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker -m symbols"
        "SUPER CTRL, SPACE, System menu, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        "SUPER, ESCAPE, System menu, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        ", XF86PowerOff, Power menu, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        "SUPER, K, Show keybindings, exec, ${pkgs.hyprland}/bin/hyprctl bindlist"

        # ─── Window Management ───
        "SUPER, W, Close window, killactive,"
        "SUPER, J, Toggle window split, togglesplit,"
        "SUPER, P, Pseudo window, pseudo,"
        "SUPER, T, Toggle window floating/tiling, togglefloating,"
        "SUPER, F, Full screen, fullscreen, 0"
        "SUPER CTRL, F, Tiled full screen, fullscreenstate, 0 2"
        "SUPER ALT, F, Full width, fullscreen, 1"

        # ─── Focus Movement ───
        "SUPER, LEFT, Move window focus left, movefocus, l"
        "SUPER, RIGHT, Move window focus right, movefocus, r"
        "SUPER, UP, Move window focus up, movefocus, u"
        "SUPER, DOWN, Move window focus down, movefocus, d"

        # ─── Workspace Switching ───
        "SUPER, code:10, Switch to workspace 1, workspace, 1"
        "SUPER, code:11, Switch to workspace 2, workspace, 2"
        "SUPER, code:12, Switch to workspace 3, workspace, 3"
        "SUPER, code:13, Switch to workspace 4, workspace, 4"
        "SUPER, code:14, Switch to workspace 5, workspace, 5"
        "SUPER, code:15, Switch to workspace 6, workspace, 6"
        "SUPER, code:16, Switch to workspace 7, workspace, 7"
        "SUPER, code:17, Switch to workspace 8, workspace, 8"
        "SUPER, code:18, Switch to workspace 9, workspace, 9"
        "SUPER, code:19, Switch to workspace 10, workspace, 10"

        # ─── Move Window to Workspace ───
        "SUPER SHIFT, code:10, Move window to workspace 1, movetoworkspace, 1"
        "SUPER SHIFT, code:11, Move window to workspace 2, movetoworkspace, 2"
        "SUPER SHIFT, code:12, Move window to workspace 3, movetoworkspace, 3"
        "SUPER SHIFT, code:13, Move window to workspace 4, movetoworkspace, 4"
        "SUPER SHIFT, code:14, Move window to workspace 5, movetoworkspace, 5"
        "SUPER SHIFT, code:15, Move window to workspace 6, movetoworkspace, 6"
        "SUPER SHIFT, code:16, Move window to workspace 7, movetoworkspace, 7"
        "SUPER SHIFT, code:17, Move window to workspace 8, movetoworkspace, 8"
        "SUPER SHIFT, code:18, Move window to workspace 9, movetoworkspace, 9"
        "SUPER SHIFT, code:19, Move window to workspace 10, movetoworkspace, 10"

        # ─── Move Window Silently ───
        "SUPER SHIFT ALT, code:10, Move window silently to workspace 1, movetoworkspacesilent, 1"
        "SUPER SHIFT ALT, code:11, Move window silently to workspace 2, movetoworkspacesilent, 2"
        "SUPER SHIFT ALT, code:12, Move window silently to workspace 3, movetoworkspacesilent, 3"
        "SUPER SHIFT ALT, code:13, Move window silently to workspace 4, movetoworkspacesilent, 4"
        "SUPER SHIFT ALT, code:14, Move window silently to workspace 5, movetoworkspacesilent, 5"
        "SUPER SHIFT ALT, code:15, Move window silently to workspace 6, movetoworkspacesilent, 6"
        "SUPER SHIFT ALT, code:16, Move window silently to workspace 7, movetoworkspacesilent, 7"
        "SUPER SHIFT ALT, code:17, Move window silently to workspace 8, movetoworkspacesilent, 8"
        "SUPER SHIFT ALT, code:18, Move window silently to workspace 9, movetoworkspacesilent, 9"
        "SUPER SHIFT ALT, code:19, Move window silently to workspace 10, movetoworkspacesilent, 10"

        # ─── Scratchpad ───
        "SUPER, S, Toggle scratchpad, togglespecialworkspace, scratchpad"
        "SUPER ALT, S, Move window to scratchpad, movetoworkspacesilent, special:scratchpad"

        # ─── Workspace Cycling ───
        "SUPER, TAB, Next workspace, workspace, e+1"
        "SUPER SHIFT, TAB, Previous workspace, workspace, e-1"
        "SUPER CTRL, TAB, Former workspace, workspace, previous"

        # ─── Move Workspace to Monitor ───
        "SUPER SHIFT ALT, LEFT, Move workspace to left monitor, movecurrentworkspacetomonitor, l"
        "SUPER SHIFT ALT, RIGHT, Move workspace to right monitor, movecurrentworkspacetomonitor, r"
        "SUPER SHIFT ALT, UP, Move workspace to up monitor, movecurrentworkspacetomonitor, u"
        "SUPER SHIFT ALT, DOWN, Move workspace to down monitor, movecurrentworkspacetomonitor, d"

        # ─── Swap Windows ───
        "SUPER SHIFT, LEFT, Swap window to the left, swapwindow, l"
        "SUPER SHIFT, RIGHT, Swap window to the right, swapwindow, r"
        "SUPER SHIFT, UP, Swap window up, swapwindow, u"
        "SUPER SHIFT, DOWN, Swap window down, swapwindow, d"

        # ─── Cycle Windows ───
        "ALT, TAB, Cycle to next window, cyclenext,"
        "ALT SHIFT, TAB, Cycle to prev window, cyclenext, prev"

        # ─── Resize ───
        "SUPER, code:20, Expand window left, resizeactive, -100 0"
        "SUPER, code:21, Shrink window left, resizeactive, 100 0"
        "SUPER SHIFT, code:20, Shrink window up, resizeactive, 0 -100"
        "SUPER SHIFT, code:21, Expand window down, resizeactive, 0 100"

        # ─── Groups ───
        "SUPER, G, Toggle window grouping, togglegroup,"
        "SUPER ALT, G, Move active window out of group, moveoutofgroup,"
        "SUPER ALT, LEFT, Move window to group on left, moveintogroup, l"
        "SUPER ALT, RIGHT, Move window to group on right, moveintogroup, r"
        "SUPER ALT, UP, Move window to group on top, moveintogroup, u"
        "SUPER ALT, DOWN, Move window to group on bottom, moveintogroup, d"
        "SUPER ALT, TAB, Next window in group, changegroupactive, f"
        "SUPER ALT SHIFT, TAB, Previous window in group, changegroupactive, b"
        "SUPER CTRL, LEFT, Move grouped window focus left, changegroupactive, b"
        "SUPER CTRL, RIGHT, Move grouped window focus right, changegroupactive, f"

        # ─── Clipboard ───
        "SUPER, C, Universal copy, sendshortcut, CTRL, Insert,"
        "SUPER, V, Universal paste, sendshortcut, SHIFT, Insert,"
        "SUPER, X, Universal cut, sendshortcut, CTRL, X,"
        "SUPER CTRL, V, Clipboard manager, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker -m clipboard"

        # ─── Mouse Bindings ───
        "SUPER, mouse_down, Scroll workspace forward, workspace, e+1"
        "SUPER, mouse_up, Scroll workspace backward, workspace, e-1"

        # ─── Media Keys ───
        ", XF86AudioRaiseVolume, Volume up, exec, $osdclient --output-volume raise"
        ", XF86AudioLowerVolume, Volume down, exec, $osdclient --output-volume lower"
        ", XF86AudioMute, Mute, exec, $osdclient --output-volume mute-toggle"
        ", XF86AudioMicMute, Mute microphone, exec, $osdclient --input-volume mute-toggle"
        ", XF86MonBrightnessUp, Brightness up, exec, $osdclient --brightness raise"
        ", XF86MonBrightnessDown, Brightness down, exec, $osdclient --brightness lower"

        # ─── Precise Media Adjustments ───
        "ALT, XF86AudioRaiseVolume, Volume up precise, exec, $osdclient --output-volume +1"
        "ALT, XF86AudioLowerVolume, Volume down precise, exec, $osdclient --output-volume -1"
        "ALT, XF86MonBrightnessUp, Brightness up precise, exec, $osdclient --brightness +1"
        "ALT, XF86MonBrightnessDown, Brightness down precise, exec, $osdclient --brightness -1"

        # ─── Media Playback ───
        ", XF86AudioNext, Next track, exec, ${pkgs.playerctl}/bin/playerctl next"
        ", XF86AudioPause, Pause, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
        ", XF86AudioPlay, Play, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
        ", XF86AudioPrev, Previous track, exec, ${pkgs.playerctl}/bin/playerctl previous"

        # ─── Audio Output Switch ───
        "SUPER, XF86AudioMute, Switch audio output, exec, ${pkgs.pamixer}/bin/pamixer --default-source toggle"

        # ─── Aesthetics ───
        "SUPER SHIFT, SPACE, Toggle top bar, exec, ${pkgs.procps}/bin/pkill waybar || ${pkgs.waybar}/bin/waybar &"
        "SUPER, BACKSPACE, Toggle window transparency, exec, ${pkgs.hyprland}/bin/hyprctl dispatch setprop \"address:$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.address')\" opaque toggle"

        # ─── Notifications ───
        "SUPER, COMMA, Dismiss last notification, exec, ${pkgs.mako}/bin/makoctl dismiss"
        "SUPER SHIFT, COMMA, Dismiss all notifications, exec, ${pkgs.mako}/bin/makoctl dismiss --all"
        "SUPER CTRL, COMMA, Toggle DND, exec, ${pkgs.mako}/bin/makoctl mode -t do-not-disturb && ${pkgs.libnotify}/bin/notify-send 'Notifications silenced' || ${pkgs.libnotify}/bin/notify-send 'Notifications enabled'"
        "SUPER ALT, COMMA, Invoke last notification, exec, ${pkgs.mako}/bin/makoctl invoke"
        "SUPER SHIFT ALT, COMMA, Restore last notification, exec, ${pkgs.mako}/bin/makoctl restore"

        # ─── Toggle Idling ───
        "SUPER CTRL, I, Toggle locking on idle, exec, ${pkgs.hypridle}/bin/hypridle --toggle"

        # ─── Nightlight ───
        "SUPER CTRL, N, Toggle nightlight, exec, ${pkgs.hyprsunset}/bin/hyprsunset -t 4500 &; sleep 1; ${pkgs.procps}/bin/pkill hyprsunset || true"

        # ─── Screenshots ───
        ", PRINT, Screenshot with editing, exec, ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.swappy}/bin/swappy -f -"
        "SHIFT, PRINT, Screenshot to clipboard, exec, ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
        "SUPER, PRINT, Color picker, exec, ${pkgs.procps}/bin/pkill hyprpicker || ${pkgs.hyprpicker}/bin/hyprpicker -a"

        # ─── Lock Screen ───
        "SUPER CTRL, L, Lock system, exec, ${pkgs.hyprlock}/bin/hyprlock"

        # ─── Control Panels ───
        "SUPER CTRL, A, Audio controls, exec, uwsm app -- ${pkgs.pavucontrol}/bin/pavucontrol"
        "SUPER CTRL, B, Bluetooth controls, exec, uwsm app -- ${pkgs.blueman}/bin/blueman-manager"
        "SUPER CTRL, W, Wifi controls, exec, uwsm app -- ${pkgs.networkmanagerapplet}/bin/nm-connection-editor"
        "SUPER CTRL, T, Activity, exec, uwsm app -- ${pkgs.foot}/bin/foot -e btop"
      ];

      bindm = [
        "SUPER, mouse:272, Move window, movewindow"
        "SUPER, mouse:273, Resize window, resizewindow"
      ];

      # ─── Exec-once (Autostart) ───
      exec-once = [
        "uwsm app -- hypridle"
        "uwsm app -- mako"
        "uwsm app -- waybar"
        "uwsm app -- fcitx5"
        "uwsm app -- swaybg -i ${wallpaper} -m fill"
        "uwsm app -- swayosd-server"
        "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" # NixOS path differs, see note
        "systemctl --user import-environment $(env | cut -d'=' -f 1)"
        "dbus-update-activation-environment --systemd --all"
      ];
    };

    # ─── Hypridle ───
    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "${pkgs.hyprlock}/bin/hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          inhibit_sleep = 3;
        };

        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
            on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on && ${pkgs.brightnessctl}/bin/brightnessctl -r";
          }
          {
            timeout = 900;
            on-timeout = "systemctl suspend";
          }
        ];
      };
    };
  };

  # ─── Hyprlock ───
  programs.hyprlock = {
    enable = true;

    settings = {
      general.ignore_empty_input = true;

      background = {
        monitor = "";
        color = "rgba(250,244,237, 1.0)";
        path = wallpaper;
        blur_passes = 3;
      };

      animations.enabled = false;

      input-field = {
        monitor = "";
        size = "650, 100";
        position = "0, 0";
        halign = "center";
        valign = "center";
        inner_color = "rgba(250,244,237, 0.8)";
        outer_color = "rgba(87,82,121, 1.0)";
        outline_thickness = 4;
        font_family = "CaskaydiaMono Nerd Font";
        font_color = "rgba(87,82,121, 1.0)";
        placeholder_text = "Enter Password";
        check_color = "rgba(86,148,159, 1.0)";
        fail_text = "<i>$FAIL ($ATTEMPTS)</i>";
        rounding = 0;
        shadow_passes = 0;
        fade_on_empty = false;
      };
    };
  };

  # ─── Hyprsunset ───
  services.hyprsunset = {
    enable = true;
  };

  # ─── Mako (Notifications) ───
  services.mako = {
    enable = true;

    settings = {
      anchor = "top-right";
      default-timeout = 5000;
      width = 420;
      "outer-margin" = 20;
      padding = "10,15";
      "border-size" = 2;
      "max-icon-size" = 32;
      font = "sans-serif 14px";

      "urgency=critical" = {
        default-timeout = 0;
        layer = "overlay";
      };

      "mode=do-not-disturb" = {
        invisible = true;
      };
    };

    # Rose Pine Dawn colors
    extraConfig = ''
      text-color=#575279
      border-color=#56949f
      background-color=#faf4ed
    '';
  };
}
```

### Step 4.3: home/features/waybar.nix

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        reload_style_on_change = true;
        layer = "top";
        position = "top";
        spacing = 0;
        height = 26;

        modules-left = ["hyprland/workspaces"];
        modules-center = ["clock"];
        modules-right = [
          "group/tray-expander"
          "bluetooth"
          "network"
          "pulseaudio"
          "battery"
          "cpu"
        ];

        "hyprland/workspaces" = {
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            default = "";
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            "7" = "7";
            "8" = "8";
            "9" = "9";
            "10" = "0";
            active = "󱓻";
          };
          persistent-workspaces = {
            "1" = [];
            "2" = [];
            "3" = [];
            "4" = [];
            "5" = [];
          };
        };

        cpu = {
          interval = 5;
          format = "󰍛";
          on-click = "uwsm app -- ${pkgs.foot}/bin/foot -e btop";
        };

        clock = {
          format = "{:L%A %H:%M}";
          "format-alt" = "{:L%d %B W%V %Y}";
          tooltip = false;
        };

        network = {
          format-icons = ["󰤯" "󰤟" "󰤢" "󰤥" "󰤨"];
          format = "{icon}";
          "format-wifi" = "{icon}";
          "format-ethernet" = "󰀂";
          "format-disconnected" = "󰤮";
          "tooltip-format-wifi" = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
          "tooltip-format-ethernet" = "⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
          "tooltip-format-disconnected" = "Disconnected";
          interval = 3;
          spacing = 1;
        };

        bluetooth = {
          format = "";
          "format-disabled" = "󰂲";
          "format-off" = "󰂲";
          "format-connected" = "󰂱";
          "format-no-controller" = "";
          "tooltip-format" = "Devices connected: {num_connections}";
        };

        pulseaudio = {
          format = "{icon}";
          "format-muted" = "";
          "format-icons" = {
            headphone = "";
            default = ["" "" ""];
          };
          "tooltip-format" = "Playing at {volume}%";
          "scroll-step" = 5;
          "on-click-right" = "${pkgs.pamixer}/bin/pamixer -t";
        };

        battery = {
          interval = 30;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon}";
          "format-full" = "󰁹";
          "format-charging" = "󰂄";
          "format-icons" = ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰂃"];
          "tooltip-format" = "{capacity}% ({timeTo})";
        };

        "group/tray-expander" = {
          orientation = "inherit";
          drawer = {
            "transition-duration" = 600;
            "children-class" = "tray-group-item";
          };
          modules = ["custom/expand-icon" "tray"];
        };

        "custom/expand-icon" = {
          format = " ";
          tooltip = false;
        };

        tray = {
          "icon-size" = 12;
          spacing = 12;
        };
      };
    };

    # Rose Pine Dawn themed CSS
    style = ''
      @define-color foreground #575279;
      @define-color background #faf4ed;

      * {
        background-color: @background;
        color: @foreground;
        border: none;
        border-radius: 0;
        min-height: 0;
        font-family: 'CaskaydiaMono Nerd Font';
        font-size: 12px;
      }

      .modules-left {
        margin-left: 8px;
      }

      .modules-right {
        margin-right: 8px;
      }

      #workspaces button {
        all: initial;
        padding: 0 6px;
        margin: 0 1.5px;
        min-width: 9px;
      }

      #workspaces button.empty {
        opacity: 0.5;
      }

      #cpu,
      #pulseaudio,
      #battery,
      #custom-expand-icon {
        min-width: 12px;
        margin: 0 7.5px;
      }

      #battery.warning {
        color: #ea9d34;
      }

      #battery.critical {
        color: #b4637a;
      }

      #tray {
        margin-right: 16px;
      }

      #bluetooth {
        margin-right: 17px;
      }

      #network {
        margin-right: 13px;
      }

      tooltip {
        padding: 2px;
      }

      #clock {
        margin-left: 5px;
      }

      .hidden {
        opacity: 0;
      }
    '';
  };
}
```

### Step 4.4: home/features/terminals.nix

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  # ─── Alacritty (Primary Terminal) ───
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      font = {
        normal = {family = "CaskaydiaMono Nerd Font"; style = "Regular";};
        bold = {family = "CaskaydiaMono Nerd Font"; style = "Bold";};
        italic = {family = "CaskaydiaMono Nerd Font"; style = "Italic";};
        size = 12.5;
      };

      window = {
        padding = {x = 5; y = 5;};
        decorations = "None";
      };

      keyboard.bindings = [
        {key = "F11"; action = "ToggleFullscreen";}
        {key = "Return"; mods = "Shift"; chars = "\\u001b[13;2u";}
      ];

      terminal.shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = ["-l"];
      };

      # Rose Pine Dawn colors
      colors = {
        primary = {
          background = "#faf4ed";
          foreground = "#575279";
        };

        cursor = {
          text = "#faf4ed";
          cursor = "#cecacd";
        };

        "vi_mode_cursor" = {
          text = "#faf4ed";
          cursor = "#cecacd";
        };

        search.matches = {
          foreground = "#faf4ed";
          background = "#ea9d34";
        };

        search."focused_match" = {
          foreground = "#faf4ed";
          background = "#b4637a";
        };

        "footer_bar" = {
          foreground = "#faf4ed";
          background = "#575279";
        };

        selection = {
          text = "#575279";
          background = "#dfdad9";
        };

        normal = {
          black = "#f2e9e1";
          red = "#b4637a";
          green = "#286983";
          yellow = "#ea9d34";
          blue = "#56949f";
          magenta = "#907aa9";
          cyan = "#d7827e";
          white = "#575279";
        };

        bright = {
          black = "#9893a5";
          red = "#b4637a";
          green = "#286983";
          yellow = "#ea9d34";
          blue = "#56949f";
          magenta = "#907aa9";
          cyan = "#d7827e";
          white = "#575279";
        };
      };
    };
  };

  # ─── Kitty ───
  programs.kitty = {
    enable = true;

    settings = {
      font_family = "CaskaydiaMono Nerd Font";
      bold_italic_font = "auto";
      font_size = 9;

      window_padding_width = 14;
      window_padding_height = 14;
      hide_window_decorations = "yes";
      show_window_resize_notification = "no";
      confirm_os_window_close = 0;

      single_instance = "yes";
      allow_remote_control = "yes";

      cursor_shape = "block";
      enable_audio_bell = "no";

      tab_bar_edge = "bottom";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      tab_title_template = "{title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}";

      # Rose Pine Dawn colors
      foreground = "#575279";
      background = "#faf4ed";
      selection_foreground = "#575279";
      selection_background = "#dfdad9";
      cursor = "#cecacd";
      cursor_text_color = "#faf4ed";
      active_border_color = "#56949f";
      active_tab_background = "#56949f";

      color0 = "#f2e9e1";
      color1 = "#b4637a";
      color2 = "#286983";
      color3 = "#ea9d34";
      color4 = "#56949f";
      color5 = "#907aa9";
      color6 = "#d7827e";
      color7 = "#575279";
      color8 = "#9893a5";
      color9 = "#b4637a";
      color10 = "#286983";
      color11 = "#ea9d34";
      color12 = "#56949f";
      color13 = "#907aa9";
      color14 = "#d7827e";
      color15 = "#575279";
    };

    keybindings = {
      "f11" = "toggle_fullscreen";
      "ctrl+insert" = "copy_to_clipboard";
      "shift+insert" = "paste_from_clipboard";
    };
  };

  # ─── Ghostty ───
  # Ghostty doesn't have home-manager support yet, use xdg config file
  xdg.configFile."ghostty/config".text = ''
    font-family = "CaskaydiaMono Nerd Font"
    font-style = Regular
    font-size = 9

    window-padding-x = 14
    window-padding-y = 14
    confirm-close-surface = false
    resize-overlay = never

    cursor-style = block
    cursor-style-blink = false

    keybind = f11=toggle_fullscreen
    keybind = shift+insert=paste_from_clipboard
    keybind = control+insert=copy_to_clipboard

    mouse-scroll-multiplier = 0.95

    background = #faf4ed
    foreground = #575279
    cursor-color = #cecacd
    selection-background = #dfdad9
    selection-foreground = #575279

    palette = 0=#f2e9e1
    palette = 1=#b4637a
    palette = 2=#286983
    palette = 3=#ea9d34
    palette = 4=#56949f
    palette = 5=#907aa9
    palette = 6=#d7827e
    palette = 7=#575279
    palette = 8=#9893a5
    palette = 9=#b4637a
    palette = 10=#286983
    palette = 11=#ea9d34
    palette = 12=#56949f
    palette = 13=#907aa9
    palette = 14=#d7827e
    palette = 15=#575279
  '';
}
```

---

## Phase 5: Home Manager Configuration

### Step 5.1: home/features/shell.nix

```nix
{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  programs.zsh = {
    enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "refined";
      plugins = [
        "git"
        "you-should-use"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
      ];
      custom = "$HOME/.oh-my-zsh/custom";
    };

    initExtra = ''
      # oh-my-zsh plugin installations (if not found)
      # zsh-autosuggestions and zsh-syntax-highlighting need to be cloned
      if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
      fi
      if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
      fi
      if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/you-should-use" ]; then
        git clone https://github.com/MichaelAquilina/zsh-you-should-use "$HOME/.oh-my-zsh/custom/plugins/you-should-use"
      fi
    '';

    shellAliases = {
      vim = "nvim";
      vi = "nvim";
      ls = "eza -lh --group-directories-first --icons=auto";
      lsa = "ls -a";
      lt = "eza --tree --level=2 --long --icons --git";
      lta = "lt -a";
      ff = "fzf --preview 'bat --style=numbers --color=always {}'";
      decompress = "tar -xzf";
    };

    envExtra = ''
      export LANG=en_US.UTF-8
      export LC_CTYPE=en_US.UTF-8
      export LC_ALL="en_US.UTF-8"
      export TERM="xterm-256color"
      export TERMINAL=alacritty
      export EDITOR="nvim"
      export SUDO_EDITOR="$EDITOR"
    '';
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = true;
      command_timeout = 200;
      format = "[$directory$git_branch$git_status]($style)$character";

      character = {
        error_symbol = "[✗](bold cyan)";
        success_symbol = "[❯](bold cyan)";
      };

      directory = {
        truncation_length = 2;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
      };

      git_branch = {
        format = "[$branch]($style) ";
        style = "italic cyan";
      };

      git_status = {
        format = "[$all_status]($style)";
        style = "cyan";
        ahead = "⇡\${count} ";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count} ";
        behind = "⇣\${count} ";
        conflicted = " ";
        up_to_date = " ";
        untracked = "? ";
        modified = " ";
        stashed = "";
        staged = "";
        renamed = "";
        deleted = "";
      };
    };
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = true;
      sync_address = "https://nuc01.tetra-banded.ts.net/atuin/";
      enter_accept = true;
      search_mode = "fuzzy";
      records = true;
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
  };

  programs.bat = {
    enable = true;
  };

  programs.fd = {
    enable = true;
  };

  programs.ripgrep = {
    enable = true;
  };
}
```

### Step 5.2: home/features/editors.nix

```nix
{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # ─── Neovim ───
  # LazyVim is best managed outside home-manager since it manages its own plugins.
  # Just ensure nvim is installed and the config directory is linked.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
  };

  # ─── Git ───
  programs.git = {
    enable = true;
    userName = "Salahuddin Muhammad Iqbal";
    userEmail = "salahuddin.mi@gmail.com";

    aliases = {
      co = "checkout";
      br = "branch";
      ci = "commit";
      st = "status";
      lg = "log --oneline --graph --decorate --all";
      last = "log -1 HEAD";
      unstage = "reset HEAD --";
      amend = "commit --amend";
    };

    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rerere.enabled = true;
      diff.colorMoved = "default";
    };

    signing = {
      key = null; # Set up GPG signing later
      signByDefault = false;
    };
  };

  # ─── Lazygit ───
  programs.lazygit = {
    enable = true;
  };

  # ─── tmux ───
  programs.tmux = {
    enable = true;

    plugins = with pkgs.tmuxPlugins; [
      tmux-sensible
      tmux-resurrect
      tmux-continuum
      tmux-battery
      vim-tmux-navigator
      tmux-yank
    ];

    extraConfig = ''
      # Continuum & Resurrect settings
      set -g @continuum-restore on
      set -g @continuum-save-interval 10
      set -g @resurrect-capture-pane-contents on
      set -g @resurrect-strategy-nvim session

      # General Settings
      set-option -g default-shell ${pkgs.zsh}/bin/zsh
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",*:RGB"
      set -g history-limit 50000
      set -g mouse on
      set -g status-position top
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -s escape-time 0
      set -g focus-events on
      set -g detach-on-destroy off
      setw -g aggressive-resize on
      set -g extended-keys on

      # Copy mode (Vi style)
      setw -g mode-keys vi
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel

      # Prefix (C-a)
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix

      # Reload config
      bind q source-file ~/.config/tmux/tmux.conf \\; display "Configuration reloaded"

      # Pane splitting
      bind v split-window -h -c "#{pane_current_path}"
      bind h split-window -v -c "#{pane_current_path}"
      bind x kill-pane
      bind c new-window -c "#{pane_current_path}"

      # Vim-Tmux Navigator
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
      bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "select-pane -L"
      bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "select-pane -D"
      bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "select-pane -U"
      bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "select-pane -R"

      # Pane Navigation (Alt+Ctrl+Arrows)
      bind -n C-M-Left select-pane -L
      bind -n C-M-Right select-pane -R
      bind -n C-M-Up select-pane -U
      bind -n C-M-Down select-pane -D

      # Pane Resizing
      bind -n C-M-S-Left resize-pane -L 5
      bind -n C-M-S-Down resize-pane -D 5
      bind -n C-M-S-Up resize-pane -U 5
      bind -n C-M-S-Right resize-pane -R 5

      # Window Navigation
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9
      bind -n M-Left select-window -t -1
      bind -n M-Right select-window -t +1

      # Management
      bind r command-prompt -I "#W" "rename-window -- '%%'"
      bind R command-prompt -I "#S" "rename-session -- '%%'"
      bind K kill-session
      bind P switch-client -p
      bind N switch-client -n

      # Fix Shift+Enter
      bind-key -n S-Enter send-keys Escape "[13;2u"

      # Rose Pine Dawn theme for tmux status bar
      set-option -g status-style bg=#EFE9E2,fg=colour241
      set-window-option -g window-status-current-style bg=#EFE9E2,fg=colour223
      set-window-option -g window-status-separator ""
      set-window-option -g window-status-format "#[bg=colour239,fg=colour246] #I  #W #[bg=#EFE9E2,fg=colour239]"
      set-window-option -g window-status-current-format "#[bg=colour208,fg=colour235] #I  #W #[bg=#EFE9E2,fg=colour208]"
      set-option -g pane-active-border-style fg=colour24,bg=#EFE9E2
      set-option -g status-left-length 80
      set-option -g status-right-length 80
      set-option -g status-left "#[bg=colour241,fg=colour248] #S #[bg=#EFE9E2,fg=colour241]"
      set-option -g status-right "#[bg=#EFE9E2,fg=colour239]#[bg=colour239,fg=colour246] %Y-%m-%d  %H:%M #{battery_color_fg}#[bg=colour239]#{battery_color_bg}#[fg=colour223] #{battery_percentage} "
    '';
  };
}
```

### Step 5.3: home/features/fcitx5.nix

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs.fcitx5-addons; [
        mozc
        fcitx5-chinese-addons # For CJK support
      ];
    };
  };

  # Fcitx5 environment variables are already set in Hyprland config
  # via the env declarations, but let's also set them in home.sessionVariables
  # for non-Hyprland contexts
  home.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };

  # Fcitx5 configuration for Mozc
  xdg.configFile."fcitx5/conf/xcb.conf".text = ''
    Allow Overriding System XKB Settings=False
    Always set layout to the default layout only=False
  '';

  xdg.configFile."fcitx5/profile".text = ''
    [Groups/0]
    Name=Default
    Default Layout=us
    DefaultIM=mozc

    [Groups/0/Items/0]
    Name=keyboard-us
    Layout=

    [Groups/0/Items/1]
    Name=mozc
    Layout=
  '';
}
```

### Step 5.4: home/common.nix

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
  home = {
    username = username;
    homeDirectory = "/home/${username}";
    stateVersion = "25.05";
  };

  # ─── Packages ───
  home.packages = with pkgs; [
    # CLI essentials (from current Omarchy setup)
    eza
    bat
    fd
    ripgrep
    fzf
    btop
    fastfetch
    lazygit
    lazydocker
    starship
    atuin
    zoxide
    direnv
    nix-direnv

    # Download managers
    wget
    curl

    # Archive
    unzip
    p7zip

    # Networking
    tailscale

    # Security
    _1password-gui
    bitwarden

    # Productivity
    obsidian

    # Communication
    signal-desktop
    slack
    tdesktop

    # Browser
    brave

    # Multimedia
    playerctl
    pamixer
    brightnessctl

    # Dev tools (system-level ones)
    mise # Language version manager (node, go, python, etc.)

    # Nix helpers
    nh # Nix Helper for rebuilds
    nix-output-monitor

    # Git
    lazygit

    # File manager
    nautilus

    # Screen utilities
    grim
    slurp
    swappy
    wl-clipboard

    # Misc
    jq
    file
    which
  ];

  # ─── Apps that need special handling ───
  # Discord: use webapp via Brave or flatpak
  # Brave is available in nixpkgs as `brave`

  # ─── xdg-mime defaults ───
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "text/plain" = "nvim.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/mailto" = "brave-browser.desktop";
    };
  };

  # ─── Home Manager itself ───
  programs.home-manager.enable = true;
}
```

### Step 5.5: home/features/theme-rose-pine.nix

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  rose-pine-dawn = {
    background = "#faf4ed";
    foreground = "#575279";
    cursor = "#cecacd";
    selection-bg = "#dfdad9";
    accent = "#56949f";

    # Normal colors
    black = "#f2e9e1";
    red = "#b4637a";
    green = "#286983";
    yellow = "#ea9d34";
    blue = "#56949f";
    magenta = "#907aa9";
    cyan = "#d7827e";
    white = "#575279";

    # Bright colors
    bright-black = "#9893a5";
    bright-red = "#b4637a";
    bright-green = "#286983";
    bright-yellow = "#ea9d34";
    bright-blue = "#56949f";
    bright-magenta = "#907aa9";
    bright-cyan = "#d7827e";
    bright-white = "#575279";
  };
in {
  # ─── GTK Theme ───
  # Use rose-pine-nix module for GTK
  rose-pine = {
    enable = true;
    flavor = "dawn";
    gtk.enable = true;
    gtk.iconTheme = "rose-pine";
    cursor.enable = true;
    cursor.package = pkgs.rose-pine-cursor;
    cursor.name = "rose-pine-dawn-cursor";
  };

  # ─── Cursor size ───
  home.pointerCursor = {
    name = "rose-pine-dawn-cursor";
    package = pkgs.rose-pine-cursor;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # ─── dconf settings for GTK ───
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-light";
      gtk-theme = "rose-pine-dawn";
      icon-theme = "Yaru-blue";
      cursor-theme = "rose-pine-dawn-cursor";
      cursor-size = 24;
      font-name = "CaskaydiaMono Nerd Font 12";
    };
  };

  # ─── GTK2/3/4 settings ───
  gtk = {
    enable = true;
    theme = {
      name = "rose-pine-dawn";
      package = pkgs.rose-pine-gtk-theme;
    };
    iconTheme = {
      name = "Yaru-blue";
      package = pkgs.yaru-theme;
    };
    cursorTheme = {
      name = "rose-pine-dawn-cursor";
      package = pkgs.rose-pine-cursor;
      size = 24;
    };
    font = {
      name = "CaskaydiaMono Nerd Font";
      size = 12;
    };
    gtk3.extraConfig = {
      gtk-xft-antialias = 1;
      gtk-xft-hinting = 1;
      gtk-xft-hintstyle = "hintslight";
      gtk-xft-rgba = "rgb";
      gtk-application-prefer-dark-theme = 0;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 0;
    };
  };

  # ─── Wallpaper ───
  # Copy your wallpaper to wallpapers/ directory
  # Then reference it in Hyprland exec-once

  # ─── qt5ct/ qt6ct ───
  home.sessionVariables = {
    QT_STYLE_OVERRIDE = "kvantum";
  };

  # Export color variables for other modules to reference
  _rosePineDawn = rose-pine-dawn;
}
```

### home/sakura.nix

```nix
{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # Host-specific home-manager settings for sakura
  # Currently minimal; add sakura-specific overrides here

  # Wallpaper path (will be set after copying wallpaper)
  # xdg.configFile."omarchy/current/background".source = ../../wallpapers/sakura-bg.jpg;
}
```

---

## Phase 6: Omarchy Trait Replication (Minimal Replacements)

### What We Replace Directly

| Omarchy Command | NixOS Replacement |
|---|---|
| `omarchy-update` | `nh os switch .` (or `sudo nixos-rebuild switch --flake .#sakura`) |
| `omarchy-restart-waybar` | `systemctl --user restart waybar` (or `pkill waybar`) |
| `omarchy-restart-walker` | `systemctl --user restart walker` (or `pkill walker`) |
| `omarchy-restart-terminal` | Just close and reopen |
| `omarchy-lock-screen` | `hyprlock` (bound to Super+Ctrl+L) |
| `omarchy-cmd-screenshot` | `grim -g "$(slurp)" - | swappy -f -` (Print key) |
| `omarchy-toggle-nightlight` | Toggle hyprsunset (Super+Ctrl+N) |
| `omarchy-theme-set` | Edit theme variable in flake and rebuild |
| `omarchy-font-set` | Edit font in flake and rebuild |
| `omarchy-menu-keybindings` | `hyprctl bindlist` |
| `omarchy-launch-walker` | `walker` |
| `omarchy-launch-browser` | `brave` |
| `omarchy-launch-editor` | `nvim` |
| `omarchy-launch-tui lazydocker` | `foot -e lazydocker` |
| `omarchy-launch-or-focus obsidian` | `obsidian -disable-gpu --enable-wayland-ime` |
| `omarchy-cmd-terminal-cwd` | `zoxide query --interactive || pwd` |
| `omarchy-cmd-audio-switch` | Handled by swayosd |
| `omarchy-menu system` | `walker` (with system mode) |
| `omarchy-menu theme` | Edit flake and rebuild |
| `omarchy-hyprland-window-close-all` | `hyprctl dispatch exit` |
| `omarchy-toggle-idle` | `hypridle --toggle` |
| `omarchy-toggle-waybar` | `pkill waybar || waybar &` |

### Custom Scripts (packages/scripts/)

**packages/scripts/screenshot.sh:**
```bash
#!/usr/bin/env bash
# Screenshot tool: area selection → clipboard + swappy edit
grim -g "$(slurp)" - | swappy -f - &
```

**packages/scripts/volume-toggle.sh:**
```bash
#!/usr/bin/env bash
# Toggle audio output device
pactl set-default-sink $(pactl list short sinks | grep -v "$(pactl get-default-sink)" | head -1 | awk '{print $2}')
```

**packages/scripts/brightness-toggle.sh:**
```bash
#!/usr/bin/env bash
# Brightness control (for external monitors if needed)
if [ "$1" = "up" ]; then
    brightnessctl set 5%+
elif [ "$1" = "down" ]; then
    brightnessctl set 5%-
fi
```

**packages/scripts/lock-screen.sh:**
```bash
#!/usr/bin/env bash
# Lock screen and stop 1password integration
loginctl lock-session
```

To include these scripts as Nix packages, add a `default.nix` in `packages/scripts/`:

```nix
# packages/scripts/default.nix
{ pkgs, ... }:

{
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.swappy}/bin/swappy -f -
  '';

  volume-toggle = pkgs.writeShellScriptBin "volume-toggle" ''
    ${pkgs.pulseaudio}/bin/pactl set-default-sink $(${pkgs.pulseaudio}/bin/pactl list short sinks | grep -v "$(${pkgs.pulseaudio}/bin/pactl get-default-sink)" | head -1 | awk '{print $2}')
  '';

  brightness-toggle = pkgs.writeShellScriptBin "brightness-toggle" ''
    if [ "$1" = "up" ]; then
        ${pkgs.brightnessctl}/bin/brightnessctl set 5%+
    elif [ "$1" = "down" ]; then
        ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    fi
  '';

  lock-screen = pkgs.writeShellScriptBin "lock-screen" ''
    loginctl lock-session
  '';
}
```

Then in `home/common.nix`, add to `home.packages`:
```nix
let
  scripts = import ../../packages/scripts { inherit pkgs; };
in
{
  home.packages = with pkgs; [
    # ... existing packages ...
  ] ++ (with scripts; [
    screenshot
    volume-toggle
    brightness-toggle
    lock-screen
  ]);
}
```

---

## Phase 7: Post-Installation

### Step 7.1: Data Migration

```bash
# Mount the backup from your data SSD
BACKUP=/tmp/arch-backup-YYYYMMDD

# SSH keys
cp -a "$BACKUP/ssh" ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub

# GPG keys
gpg --import "$BACKUP/gnupg/"*.asc 2>/dev/null || echo "Import GPG keys manually"

# Atuin re-login
# After starting a shell, Atuin will prompt for registration
# Or copy the key:
mkdir -p ~/.local/share/atuin
cp "$BACKUP/atuin/key" ~/.local/share/atuin/key
# Then run: atuin login

# Git config (already handled by home-manager)

# Obsidian vaults — move to your preferred location
cp -a "$BACKUP/obsidian-vault" ~/Documents/

# Browser data — use Brave sync to restore bookmarks/extensions
# OR manually copy:
# cp -a "$BACKUP/brave-profile" ~/.config/BraveSoftware/Brave-Browser/

# Neovim config
cp -a "$BACKUP/nvim" ~/.config/nvim
# Then inside nvim, run :Lazy restore to download plugins

# Tmux config (already handled by home-manager, but check)
# Starship config (already handled by home-manager)

# Custom local scripts
cp -a "$BACKUP/local-bin/"* ~/.local/bin/ 2>/dev/null
```

### Step 7.2: Applications Not in Nixpkgs

Some applications may not be in nixpkgs or may work better via alternative methods:

| Application | Approach |
|-------------|----------|
| Discord | Use Brave webapp (Super+Y → Discord web) or Flatpak |
| 1Password CLI | Install via `programs._1password` or nixpkgs package |
| Obsidian | Available in nixpkgs |
| Signal | `signal-desktop` package in nixpkgs |
| Slack | `slack` package in nixpkgs |
| Telegram | `tdesktop` package in nixpkgs |
| Brave | `brave` package in nixpkgs |
| VS Code / Cursor | Use `programs.vscode` in home-manager or download |

For Flatpak apps, enable in `hosts/common/core.nix`:
```nix
services.flatpak.enable = true;
```

### Step 7.3: NFS Mount

The tubeinas NFS mount is already configured in `hosts/sakura/default.nix`. Verify it auto-mounts after boot:

```bash
# Ensure NFS service is running
systemctl status nfs-client.target

# Test mount
ls /mnt/tubeinas

# If Tailscale is needed first, ensure the mount waits for network
# The _netdev option in the mount config handles this
```

### Step 7.4: Docker and Dev Environment

Docker is enabled in `hosts/sakura/default.nix`. After rebuild:

```bash
# Verify Docker
docker ps

# Mise setup (language version manager)
mise settings set experimental true
mise install node@lts
mise install go@latest
mise install python@latest

# For project-specific dev environments, use direnv + flake.nix per project
# Example project flake.nix:
# {
#   inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#   outputs = {nixpkgs, ...}: {
#     devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
#       packages = with nixpkgs.legacyPackages.x86_64-linux; [nodejs go python3];
#     };
#   };
# }
```

### Step 7.5: Verify Everything Works

Run through this checklist after the first successful rebuild:

```bash
# 1. Hyprland starts
# Log in via TTY/manager, Hyprland should start with UWSM
uwsm start hyprland

# 2. Waybar renders with all modules
# Check waybar is running and shows workspaces, clock, network, audio
waybar &

# 3. Japanese input works
# Press Ctrl+Space or the fcitx5 trigger to toggle input
fcitx5-diagnose  # Check for issues

# 4. Theme is consistent
# Check: Alacritty, Kitty, Ghostty, GTK apps all use Rose Pine Dawn

# 5. All keybindings work
# Press Super+Return → terminal opens
# Press Super+Space → Walker launches
# Press Super+W → window closes

# 6. Docker runs
docker run hello-world

# 7. Tailscale connects
tailscale status

# 8. Can rebuild system
cd ~/Documents/dev/kebun
nh os switch .

# 9. Screenshot key works
# Press Print → area selection → swappy editor

# 10. Volume/brightness keys work
# Use media keys, swayosd should show overlay
```

---

## hosts/common/dev.nix

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Development packages that are best installed system-wide
  environment.systemPackages = with pkgs; [
    # Core dev tools
    gcc
    gnumake
    cmake
    pkg-config

    # Language runtimes (mise handles per-project, but these are system-level)
    go
    nodejs
    python3

    # Docker tools (docker is enabled in sakura/default.nix)
    docker-compose

    # Nix dev tools
    nixfmt-rfc-style
    alejandra
    nil # Nix LSP
    nixd # Nix LSP alternative

    # Database clients
    postgresql
    sqlite
  ];

  # Docker daemon (enabled per-host in sakura/default.nix)
}
```

## hosts/common/networking.nix

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  networking = {
    networkmanager = {
      enable = true;
      dns = "default";
    };

    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443];
      allowedUDPPorts = [];
    };

    # Enable wireless (users can manage via nmcli or nmtui)
    wireless.enable = false; # NetworkManager handles this
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # NFS client
  services.nfs.client.enable = true;

  # DNS
  services.resolved = {
    enable = true;
    dnssec = "true";
    fallbackDns = ["1.1.1.1" "8.8.8.8"];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true; # Change to false after setup
      PermitRootLogin = "no";
    };
  };

  # Avahi (mDNS for local network discovery)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
```

---

## Dependency Matrix

| Task | Depends On | Blocks |
|------|-----------|--------|
| Phase 0: Backup | Nothing | Phase 1 |
| Phase 1.2: Partition | Phase 0 backup | Phase 1.3 |
| Phase 1.3: Generate config | Phase 1.2 partitions | Phase 1.4 |
| Phase 1.4: Install | Phase 1.3 config | Phase 2 |
| Phase 2: Flake setup | Phase 1.4 install | Phase 3-6 |
| Phase 3: Core config | Phase 2 flake structure | Phase 4-5 |
| Phase 4.1: desktop.nix | Phase 3 core config | Phase 4.2-4.4 |
| Phase 4.2: Hyprland config | Phase 4.1 desktop.nix | Phase 4.3-4.4 |
| Phase 4.3: Waybar | Phase 4.2 Hyprland | Phase 7 verification |
| Phase 4.4: Terminals | Phase 4.1 desktop.nix | Phase 7 verification |
| Phase 5: Home Manager | Phase 2 flake | Phase 7 verification |
| Phase 6: Scripts | Phase 5 | Phase 7 verification |
| Phase 7: Verification | All previous phases | Production use |

---

## Success Criteria

- [ ] System boots with LUKS encryption (enter passphrase at systemd-boot)
- [ ] Hyprland starts with all keybindings (Super+Return, Super+Space, etc.)
- [ ] Waybar shows workspaces, clock, network, audio, bluetooth
- [ ] Rose Pine Dawn theme applied everywhere (terminals, GTK apps, Hyprland borders)
- [ ] Japanese input (fcitx5 + Mozc) works (Ctrl+Space or fcitx5 trigger)
- [ ] All terminals (Alacritty, Kitty, Ghostty) look themed
- [ ] Zsh + oh-my-zsh + starship works with all aliases
- [ ] Docker and dev tools available and working
- [ ] Tailscale connects on boot
- [ ] Can rebuild system with `nh os switch .`
- [ ] Screenshot/volume/brightness keys work
- [ ] NFS mount (tubeinas) auto-mounts when on network
- [ ] Mako/swayosd notifications display correctly
- [ ] Hypridle locks screen after 10 minutes
- [ ] Hyprlock lock screen shows Rose Pine Dawn theme
- [ ] Atuin syncs history to self-hosted server
- [ ] tmux with all plugins and C-a prefix works
- [ ] Walker app launcher opens with Super+Space
- [ ] Monitor setup (eDP-1 1920x1080@60Hz, scale 1.5) is correct

---

## Quick Reference: Common NixOS Commands

```bash
# Rebuild system (from kebun directory)
nh os switch .                     # Recommended (uses nh)
sudo nixos-rebuild switch --flake .#sakura  # Alternative

# Rebuild home-manager only (if needed)
home-manager switch --flake .#ivokun@sakura

# Update flake inputs
nix flake update

# Check flake
nix flake check

# Enter dev shell for a specific project
nix develop

# Garbage collect old generations
nix-collect-garbage -d
sudo nix-collect-garbage -d

# List generations
nix-env --list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Search for packages
nix search nixpkgs <package-name>

# Show package info
nix profile list
```

## Troubleshooting

### LUKS not prompting for password at boot
Ensure `boot.initrd.luks.devices.root` is set correctly in `hardware-configuration.nix`. The UUID must match your partition.

### Hyprland won't start
1. Check UWSM is installed: `uwsm check may-start -vv`
2. Check Hyprland logs: `uwsm app -- hyprctl version`
3. Try starting manually: `uwsm start hyprland`

### fcitx5 not activating
1. Run `fcitx5-diagnose` to check configuration
2. Ensure environment variables are set (check `/etc/environment`)
3. Add `GTK_IM_MODULE=fcitx`, `QT_IM_MODULE=fcitx`, `XMODIFIERS=@im=fcitx` to `environment.sessionVariables` in `common/desktop.nix`

### Waybar not showing modules
1. Check waybar logs: `waybar 2>&1 | tee /tmp/waybar.log`
2. Ensure all required packages are installed (playerctl, pamixer, etc.)
3. Try restarting: `systemctl --user restart waybar`

### AMD GPU issues (Renoir / Ryzen 5 PRO 4650U)
1. Ensure `amdgpu` is in `boot.initrd.kernelModules`
2. Check kernel messages: `dmesg | grep amdgpu`
3. If screen tearing: add `env = WLR_DRM_NO_ATOMIC,1` to Hyprland env
4. For Renoir APU, ensure `amdgpu.sg_display=0` kernel param is set (already in config)
5. If external monitor not detected over USB-C: check `ls /sys/class/drm/`

### Theme inconsistency
1. Run `gsettings set org.gnome.desktop.interface gtk-theme 'rose-pine-dawn'`
2. Run `gsettings set org.gnome.desktop.interface icon-theme 'Yaru-blue'`
3. Reset qt5ct/qt6ct: `qt5ct` and `qt6ct` apps
4. If GTK apps don't pick up theme, verify `environment.sessionVariables` for GTK_THEME