# NixOS + Flakes Installation Guide

Complete step-by-step guide to install NixOS with Flakes on your Lenovo ThinkPad X13 Gen 1 and apply the `kebun` flake.

---

## Phase 0: Pre-Installation

### Step 0.1: Backup Your Arch System

Back up everything you need before wiping the NVMe drive.

```bash
# Create backup directory on external storage
mkdir -p /tmp/arch-backup-$(date +%Y%m%d)
BACKUP=/tmp/arch-backup-$(date +%Y%m%d)

# Critical data
cp -a ~/.ssh "$BACKUP/ssh"
cp -a ~/.gnupg "$BACKUP/gnupg" 2>/dev/null
cp ~/.gitconfig "$BACKUP/gitconfig"
cp -a ~/.config/starship.toml "$BACKUP/starship.toml"
cp -a ~/.config/tmux "$BACKUP/tmux"
cp -a ~/.config/nvim "$BACKUP/nvim"
cp -a ~/.local/share/atuin "$BACKUP/atuin"
cp -a ~/.local/bin "$BACKUP/local-bin" 2>/dev/null

# Atuin credentials
cp ~/.local/share/atuin/key "$BACKUP/atuin-key"
cp ~/.local/share/atuin/session "$BACKUP/atuin-session" 2>/dev/null

# Wallpaper
cp ~/.config/omarchy/current/background "$BACKUP/wallpaper"

# Package lists
pacman -Qqe > "$BACKUP/pkglist.txt"
yay -Qm > "$BACKUP/aur-list.txt" 2>/dev/null

# System config
cp /etc/fstab "$BACKUP/fstab"
blkid /dev/nvme0n1p2 > "$BACKUP/blkid-nvme.txt"

# Copy to external drive or NAS
rsync -av "$BACKUP" /path/to/external/storage/
```

### Step 0.2: Create NixOS USB

On another computer or your current Arch system:

```bash
# Download NixOS minimal ISO (unstable)
curl -L -o nixos-minimal.iso \
  https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso

# Find your USB device ( CAREFUL - double check! )
lsblk

# Write to USB (replace sdX with your USB device)
sudo dd if=nixos-minimal.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### Step 0.3: Boot from USB

1. Insert USB into ThinkPad X13
2. Power on, press **F12** for boot menu
3. Select USB drive
4. Choose **NixOS default** from bootloader
5. You'll get a root shell with `root@nixos>` prompt

---

## Phase 1: Disk Setup (LUKS + BTRFS)

### Step 1.1: Verify Boot Mode and Network

```bash
# Should show UEFI
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy"

# Set console font for readability
setfont ter-116n

# Connect to WiFi (if no wired connection)
iwctl
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect "YOUR_SSID"
[iwd]# exit

# Verify network
ping -c 3 google.com

# Optional: Enable SSH for easier copy-paste from another machine
systemctl start sshd
passwd  # Set a temporary root password
ip addr show  # Note the IP
```

### Step 1.2: Partition the Disk

**Layout:**
- `/dev/nvme0n1p1` - EFI System Partition (2GB)
- `/dev/nvme0n1p2` - LUKS encrypted container (~236GB)

```bash
# WARNING: This DESTROYS all data on /dev/nvme0n1
# Double-check you're targeting the right disk
lsblk

# Partition with gdisk
gdisk /dev/nvme0n1
# Commands inside gdisk:
#   o                    <- Create new GPT
#   Y                    <- Confirm
#   n → 1 → Enter → +2G → EF00
#   n → 2 → Enter → Enter → 8309
#   p                    <- Verify partitions
#   w                    <- Write and exit
#   Y                    <- Confirm

# Format ESP
mkfs.vfat -F 32 -n EFI /dev/nvme0n1p1

# Create LUKS container
cryptsetup luksFormat /dev/nvme0n1p2
# Enter your passphrase when prompted (strong passphrase!)

# Open LUKS container
cryptsetup open /dev/nvme0n1p2 root

# Create BTRFS filesystem
mkfs.btrfs -L nixos /dev/mapper/root

# Create subvolumes
mount /dev/mapper/root /mnt
btrfs subvolume create /mnt/@root
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@swap
umount /mnt
```

### Step 1.3: Mount Everything

```bash
# Mount root subvolume
mount -o compress=zstd:3,ssd,noatime,subvol=@root /dev/mapper/root /mnt

# Create mount points
mkdir -p /mnt/{boot,home,var/log,var/cache,nix,swap}

# Mount other subvolumes
mount -o compress=zstd:3,ssd,noatime,subvol=@home /dev/mapper/root /mnt/home
mount -o compress=zstd:3,ssd,noatime,subvol=@log /dev/mapper/root /mnt/var/log
mount -o compress=zstd:3,ssd,noatime,subvol=@cache /dev/mapper/root /mnt/var/cache
mount -o nodatacow,subvol=@swap /dev/mapper/root /mnt/swap

# Mount ESP
mount /dev/nvme0n1p1 /mnt/boot

# Create swapfile
btrfs filesystem mkswapfile --size 4g /mnt/swap/swapfile
```

---

## Phase 2: Generate Base Configuration

### Step 2.1: Generate Hardware Config

```bash
# Generate initial configuration
nixos-generate-config --root /mnt

# The generated files:
# /mnt/etc/nixos/configuration.nix
# /mnt/etc/nixos/hardware-configuration.nix
```

### Step 2.2: Inspect Hardware Config

```bash
cat /mnt/etc/nixos/hardware-configuration.nix
```

**Verify it contains:**
- `boot.initrd.luks.devices."root"` with the correct UUID
- `fileSystems."/"` with `subvol=@root`
- `fileSystems."/home"` with `subvol=@home`
- `fileSystems."/var/log"` with `neededForBoot = true`
- `fileSystems."/swap"` with `nodatacow`
- `swapDevices` pointing to `/swap/swapfile`

**Note the UUIDs** - you'll need them for the flake.

### Step 2.3: Create Minimal Installer Config

Edit `/mnt/etc/nixos/configuration.nix` to be minimal:

```nix
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "sakura";
  time.timeZone = "Asia/Tokyo";

  users.users.ivokun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
  };

  services.xserver.videoDrivers = [ "amdgpu" ];

  # Enable SSH for remote access during setup
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  system.stateVersion = "25.05";
}
```

### Step 2.4: Install Base NixOS

```bash
# Install
nixos-install

# Set root password when prompted

# Set user password
echo "ivokun:changeme" | chroot /mnt chpasswd

# Reboot
reboot
```

---

## Phase 3: Apply the Flake

### Step 3.1: First Boot

After reboot:
1. You should see systemd-boot menu
2. Select NixOS
3. Enter LUKS passphrase
4. Log in as `ivokun` / `changeme`

### Step 3.2: Connect Network

```bash
# If wired, should work automatically
# If WiFi:
nmcli device wifi list
nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"

# Verify
ping -c 3 google.com
```

### Step 3.3: Install Git and Clone Repo

```bash
# Install git
sudo nix-shell -p git

# Create directory
mkdir -p ~/Documents/dev
cd ~/Documents/dev

# Clone your repo (replace with your actual repo URL)
git clone https://github.com/ivokun/kebun.git
cd kebun
```

### Step 3.4: Copy Hardware Configuration

```bash
# Copy the generated hardware config
sudo cp /etc/nixos/hardware-configuration.nix \
  ~/Documents/dev/kebun/hosts/sakura/hardware-configuration.nix

# Verify and update UUIDs if needed
# The hardware-configuration should already have correct UUIDs from nixos-generate-config
```

### Step 3.5: Update Hardware Config (if needed)

Your hardware-configuration.nix should look like this (with your actual UUIDs):

```nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [ ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "uas" "sd_mod"];
  boot.initrd.kernelModules = ["dm-snapshot" "amdgpu"];
  boot.kernelModules = ["kvm-amd" "thinkpad_acpi"];

  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-uuid/YOUR-LUKS-UUID";
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
    options = ["subvol=@cache" "compress=zstd:3" "noatime" "ssd"];
  };

  fileSystems."/swap" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = ["subvol=@swap" "noatime" "nodatacow"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/YOUR-ESP-UUID";
    fsType = "vfat";
  };

  swapDevices = [{device = "/swap/swapfile"; size = 4096;}];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
```

### Step 3.6: Update flake.lock

```bash
cd ~/Documents/dev/kebun

# Update flake inputs
nix flake update
```

### Step 3.7: Build and Switch

```bash
# IMPORTANT: First rebuild with --impure for unfree packages
sudo NIXPKGS_ALLOW_UNFREE=1 nixos-rebuild switch --flake .#sakura --impure

# This will:
# - Download all packages
# - Build the system
# - Install everything
# - Set up home-manager
# - Configure Hyprland, Waybar, etc.
# 
# This takes 15-60 minutes depending on internet speed
```

### Step 3.8: After Successful Build

```bash
# Change your password (SECURITY - you used "changeme" initially)
passwd

# Verify the build worked
sudo nixos-rebuild switch --flake .#sakura

# Or use nh (installed by the flake)
nh os switch .
```

---

## Phase 4: Post-Installation

### Step 4.1: Copy Wallpaper

```bash
mkdir -p ~/.config/omarchy/current
cp /path/to/your/backup/wallpaper ~/.config/omarchy/current/background
```

### Step 4.2: Restore Your Data

```bash
# Mount your backup drive
# Example:
sudo mkdir -p /mnt/backup
sudo mount /dev/sdX1 /mnt/backup

# SSH keys
cp -a /mnt/backup/arch-backup-*/ssh ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub

# GPG keys
gpg --import /mnt/backup/arch-backup-*/gnupg/*.asc 2>/dev/null

# Atuin
cp /mnt/backup/arch-backup-*/atuin-key ~/.local/share/atuin/key
# Then run: atuin login

# Neovim config
cp -a /mnt/backup/arch-backup-*/nvim ~/.config/nvim
# Inside nvim, run :Lazy restore

# Custom scripts
cp -a /mnt/backup/arch-backup-*/local-bin/* ~/.local/bin/ 2>/dev/null
```

### Step 4.3: Start Hyprland

```bash
# Log out of current session (if in a graphical session)
# Or switch to a new TTY: Ctrl+Alt+F2

# Start Hyprland with UWSM
uwsm start hyprland
```

### Step 4.4: Verify Everything

```bash
# 1. Hyprland running
echo $XDG_SESSION_TYPE  # Should be "wayland"

# 2. Waybar active
systemctl --user status waybar

# 3. Japanese input
fcitx5-diagnose

# 4. Theme applied
gsettings get org.gnome.desktop.interface gtk-theme

# 5. zram active
zramctl

# 6. Docker working
docker run hello-world

# 7. Tailscale
tailscale status

# 8. Rebuild works
cd ~/Documents/dev/kebun
nh os switch .
```

---

## Phase 5: Troubleshooting

### LUKS Not Prompting at Boot

```bash
# Boot from USB, mount system, check config
sudo cryptsetup luksDump /dev/nvme0n1p2
# Verify UUID in hardware-configuration.nix matches
```

### Hyprland Won't Start

```bash
# Check UWSM
uwsm check may-start -vv

# Try manual start (from TTY)
Hyprland

# Check logs
journalctl --user -u hyprland
```

### Rebuild Fails

```bash
# Get detailed error trace
sudo nixos-rebuild switch --flake .#sakura --show-trace

# Update flake inputs
nix flake update

# Garbage collect if disk full
sudo nix-collect-garbage -d
```

### Network Issues

```bash
# Check NetworkManager
nmcli device status

# Restart
sudo systemctl restart NetworkManager

# WiFi specifically
nmcli radio wifi
nmcli device wifi rescan
```

---

## Quick Reference

```bash
# Rebuild system (from kebun directory)
nh os switch .

# Update flake inputs
nix flake update

# Check flake
nix flake check

# Rollback
sudo nixos-rebuild switch --rollback

# List generations
sudo nix-env -p /nix/var/nix/profiles/system --list-generations

# Delete old generations
sudo nix-collect-garbage -d

# Search packages
nix search nixpkgs firefox

# Enter dev shell
nix develop
```

---

**You're done!** Your ThinkPad X13 now runs NixOS with a fully declarative, reproducible configuration. Any changes you make to the flake can be applied with `nh os switch .`. Welcome to the Nix ecosystem!
