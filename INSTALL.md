# NixOS + Flakes Installation Guide

Complete step-by-step guide to install NixOS with Flakes on your Lenovo ThinkPad X13 Gen 1 (the `sakura` host) and apply the `kebun` flake.

Two hard rules while following this guide:

- **The configuration target is `sakura`.** On ivokun-htpc, validate it with `nix build .#nixosConfigurations.sakura.config.system.build.toplevel`; activation (`switch`) happens only on sakura.
- **No `nix flake update` during install.** The flake pins its inputs for a reason; the install path uses them as-is. Update a single input later only when a pinned input genuinely blocks a rebuild.

---

## Phase 0: Pre-Installation

### Step 0.1: Backup Your Arch System

Back up everything you need before wiping the NVMe drive.
The archive contains SSH and GPG private keys; copy it only to encrypted,
trusted storage and delete temporary copies when the restore is complete.

```bash
# Create backup directory on external storage
mkdir -p /tmp/arch-backup-$(date +%Y%m%d)
BACKUP=/tmp/arch-backup-$(date +%Y%m%d)

# Critical data (skip entries you do not use)
cp -a ~/.ssh "$BACKUP/ssh"
cp -a ~/.gnupg "$BACKUP/gnupg" 2>/dev/null || true
cp ~/.gitconfig "$BACKUP/gitconfig" 2>/dev/null || true
cp ~/.config/starship.toml "$BACKUP/starship.toml" 2>/dev/null || true
cp -a ~/.config/tmux "$BACKUP/tmux" 2>/dev/null || true
cp -a ~/.config/nvim "$BACKUP/nvim" 2>/dev/null || true
cp -a ~/.local/share/atuin "$BACKUP/atuin" 2>/dev/null || true
cp -a ~/.local/bin "$BACKUP/local-bin" 2>/dev/null

# Atuin credentials
cp ~/.local/share/atuin/key "$BACKUP/atuin-key" 2>/dev/null || true
cp ~/.local/share/atuin/session "$BACKUP/atuin-session" 2>/dev/null

# Package lists
pacman -Qqe > "$BACKUP/pkglist.txt"
yay -Qm > "$BACKUP/aur-list.txt" 2>/dev/null

# System config
cp /etc/fstab "$BACKUP/fstab"
blkid > "$BACKUP/blkid.txt"

# Copy to external drive or NAS
rsync -av "$BACKUP" /path/to/external/storage/
```

### Step 0.2: Create NixOS USB

On another computer or your current Arch system (htpc):

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

This matches `hosts/sakura/hardware-configuration.nix` exactly. The layout is
**two LUKS containers**, not one:

- `/dev/nvme0n1p1` — EFI System Partition (2 GB)
- `/dev/nvme0n1p2` — LUKS encrypted root (all space except the final swap
  partition), Btrfs inside with a
  default (top-level) subvolume holding `/`, plus dedicated `home` and `nix`
  subvolumes
- `/dev/nvme0n1p3` — dedicated LUKS-encrypted swap partition (8.8 GB on
  sakura; see the hibernation note below)

There are **no `@root`/`@swap` style swapfile subvolumes** — swap is a raw
LUKS partition, and `/`, `/home`, `/nix` are the only meaningful subvolumes.

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
#   n → 2 → Enter → -8.8G → 8309   (LUKS root; leave 8.8 GiB at the end)
#   n → 3 → Enter → Enter → 8309   (LUKS swap; remaining space)
#   p                    <- Verify partitions
#   w                    <- Write and exit
#   Y                    <- Confirm

# Format ESP
mkfs.vfat -F 32 -n EFI /dev/nvme0n1p1

# Create and open the root LUKS container
cryptsetup luksFormat /dev/nvme0n1p2
ROOT_UUID=$(cryptsetup luksUUID /dev/nvme0n1p2)
cryptsetup open /dev/nvme0n1p2 "luks-$ROOT_UUID"

# Create BTRFS filesystem
mkfs.btrfs -L nixos "/dev/mapper/luks-$ROOT_UUID"

# Create subvolumes
mount "/dev/mapper/luks-$ROOT_UUID" /mnt
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/nix
umount /mnt
# The filesystem's top level stays as the / mountpoint (no @root needed —
# fileSystems."/" in the flake carries no subvol= option for this reason).

# Create and open the swap LUKS container
cryptsetup luksFormat /dev/nvme0n1p3
SWAP_UUID=$(cryptsetup luksUUID /dev/nvme0n1p3)
cryptsetup open /dev/nvme0n1p3 "luks-$SWAP_UUID"
mkswap -L swap "/dev/mapper/luks-$SWAP_UUID"
swapon "/dev/mapper/luks-$SWAP_UUID"  # lets nixos-generate-config discover it

# Hibernation note: hibernating requires swap >= RAM (30.6 GB here).
# Sakura ships an 8.8 GB swap partition and therefore has hibernation
# DISABLED — see the comment block in hosts/sakura/default.nix. If you want
# working hibernation, make p3 >= RAM+2 GB instead of 8.8 GB; the rest of
# the config is unchanged, you'd just re-add boot.resumeDevice afterwards.
```

### Step 1.3: Mount Everything

```bash
# Re-read the UUIDs if this is a new shell.
ROOT_UUID=$(cryptsetup luksUUID /dev/nvme0n1p2)

# Root: default (top-level) subvolume of the btrfs FS
mount "/dev/mapper/luks-$ROOT_UUID" /mnt

# Create mount points
mkdir -p /mnt/{boot,home,nix}

# Mount subvolumes
mount -o subvol=home "/dev/mapper/luks-$ROOT_UUID" /mnt/home
mount -o subvol=nix "/dev/mapper/luks-$ROOT_UUID" /mnt/nix

# Mount ESP
mount /dev/nvme0n1p1 /mnt/boot
```

The swap device needs no mount point — NixOS consumes it via `swapDevices`
(`/dev/mapper/luks-<swap-uuid>`), which is what the flake's hardware config
declares.

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
- a root `boot.initrd.luks.devices."luks-<uuid>"` entry
- `fileSystems."/"` on `/dev/mapper/luks-…`, fsType btrfs, **no `subvol=` option**
- `fileSystems."/home"` with `subvol=home`
- `fileSystems."/nix"` with `subvol=nix`
- `fileSystems."/boot"` pointing at the ESP vfat
- `swapDevices = [{ device = "/dev/mapper/luks-…"; }]` — a raw mapped device, no size argument

The generated hardware file normally declares only the root LUKS device. Add
the swap declaration to the minimal installer configuration below so swap is
available on the bootstrap boot. The final flake declares both devices in
`hosts/sakura/default.nix`.

**Note the UUIDs** — you'll need them for the flake.

### Step 2.3: Create Minimal Installer Config

Edit `/mnt/etc/nixos/configuration.nix` to be minimal. No `initialPassword`
and no password placeholders anywhere — the account password is set
interactively right after `nixos-install` (Phase 2, Step 2.4). SSH is
key-only and accepts the htpc Ed25519 key:

```nix
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Replace this placeholder with `cryptsetup luksUUID /dev/nvme0n1p3`.
  # The generated hardware config already declares the root container.
  boot.initrd.luks.devices."luks-SWAP-LUKS-UUID".device =
    "/dev/disk/by-uuid/SWAP-LUKS-UUID";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "sakura";
  time.timeZone = "Asia/Tokyo";

  # Keep networking usable after the installer reboot. The final flake uses
  # this same iwd + systemd-networkd split.
  networking.useNetworkd = true;
  networking.wireless.iwd.enable = true;
  systemd.network = {
    enable = true;
    networks = {
      "10-wired" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = true;
      };
      "20-wifi" = {
        matchConfig.Name = "wl*";
        networkConfig.DHCP = true;
      };
    };
  };

  users.users.ivokun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Locked until the interactive passwd step after nixos-install.
    initialHashedPassword = "!";
    openssh.authorizedKeys.keys = [
      # Operator key from ivokun-htpc.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDGGZAQ+M111Mt5ii5fXs7DsPYn/iayDpmcBRhxpujvd salahuddin.mi@gmail.com"
    ];
  };

  services.xserver.videoDrivers = [ "amdgpu" ];

  # Enable SSH for remote access during setup — key auth only
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
    AllowUsers = [ "ivokun" ];
  };

  system.stateVersion = "25.05";
}
```

### Step 2.4: Install Base NixOS

```bash
# Install — nixos-install prompts for the root account password interactively
nixos-install

# Set the ivokun password interactively (no bootstrap placeholder)
nixos-enter --root /mnt -c 'passwd ivokun'

# Reboot
reboot
```

---

## Phase 3: Apply the Flake

### Step 3.1: First Boot

After reboot:
1. You should see the systemd-boot menu
2. Select NixOS
3. Enter the LUKS passphrase (both containers prompt in this phase)
4. Log in as `ivokun` with the account password you set in Phase 2

### Step 3.2: Connect Network

```bash
# If wired, should work automatically
# If WiFi:
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "YOUR_SSID"

# Verify
ping -c 3 google.com
```

### Step 3.3: Install Git and Clone Repo

```bash
# Create directory
mkdir -p ~/Documents/dev
cd ~/Documents/dev

# Clone with an ephemeral, unprivileged Git package
nix shell nixpkgs#git -c git clone https://github.com/ivokun/kebun.git
cd kebun
```

### Step 3.4: Copy Hardware Configuration

```bash
# Copy the generated hardware config without leaving a root-owned worktree file
sudo install -o ivokun -g users -m 0644 \
  /etc/nixos/hardware-configuration.nix \
  ~/Documents/dev/kebun/hosts/sakura/hardware-configuration.nix

# The generated file has this installation's UUIDs. Update the matching root
# and swap UUID/name entries in hosts/sakura/default.nix before the first
# flake build as well; that host module enables TPM2 unlock for both devices.
```

### Step 3.5: Verify Hardware Config (if needed)

Your hardware-configuration.nix should look like this (with your actual UUIDs):

```nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Preserve the module list generated for this machine. Sakura currently has:
  boot.initrd.availableKernelModules = ["nvme" "ehci_pci" "xhci_pci_renesas" "xhci_pci" "usb_storage" "sd_mod" "rtsx_pci_sdmmc"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];

  fileSystems."/" = {
    device = "/dev/mapper/luks-ROOT-LUKS-UUID";
    fsType = "btrfs";
  };

  boot.initrd.luks.devices."luks-ROOT-LUKS-UUID".device =
    "/dev/disk/by-uuid/ROOT-LUKS-UUID";

  fileSystems."/home" = {
    device = "/dev/mapper/luks-ROOT-LUKS-UUID";
    fsType = "btrfs";
    options = ["subvol=home"];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/luks-ROOT-LUKS-UUID";
    fsType = "btrfs";
    options = ["subvol=nix"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/ESP-UUID";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  swapDevices = [
    {device = "/dev/mapper/luks-SWAP-LUKS-UUID";}
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

(Remember: **no** `subvol=@root`, **no** `subvol=@swap` or swapfile entry,
**no** `@log`/`@cache`. Subvols are literally `home` and `nix`.) The two
`tpm2-device=auto` / `tpm2-measure-pcr=yes` `crypttabExtraOpts` lines come
from `hosts/sakura/default.nix`, so the generated file only needs the plain
LUKS device declarations.

### Step 3.6: TPM2 Enrollment for Both Volumes

Boot has zero prompts by design (ADR-0010): both LUKS containers auto-unlock
via TPM2 at PCR 7, and SDDM's single password is the machine's only prompt
(autologin stays off). Keep the passphrase valid on both containers in the
meantime — enrollment can always fall back to it.

PCR 7 enrollment provides unattended unlock, but it is not verified boot by
itself. This repository disables systemd-boot command-line editing but does
not provision or enroll Secure Boot signing keys. Until a separate signed
boot-chain setup exists, treat TPM auto-unlock as convenience rather than
offline-tamper resistance.

```bash
# Use the UUIDs printed by `cryptsetup luksUUID` or `blkid`.
# Enroll TPM2 unlock for the ROOT container
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-uuid/ROOT-LUKS-UUID

# Enroll TPM2 unlock for the SWAP container too
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-uuid/SWAP-LUKS-UUID
```

Both volume entries in `hosts/sakura/default.nix` already carry
`crypttabExtraOpts = ["tpm2-device=auto"]` (the root one also measures its
PCRs), so nothing further is needed after enrolling. Verify at next reboot:
both volumes should open without a passphrase prompt.

### Step 3.7: Build and Switch

```bash
# IMPORTANT: activate on sakura, from sakura's checkout
sudo nixos-rebuild switch --flake .#sakura

# This will:
# - Download all packages
# - Build the system
# - Install everything
# - Set up home-manager
# - Configure Hyprland via UWSM, quickshell (omarchy-shell), etc.
#
# This takes 15-60 minutes depending on internet speed
```

After a successful switch:

```bash
# Use nh from now on (installed from nixpkgs by home/common.nix)
nh os switch .
```

### Step 3.8: Tailscale + SSH

Once the flake is active, SSH access is through **Tailscale** with
**key-only authentication** (no password auth) against the htpc Ed25519
authorized key configured in Step 2.3:

```bash
# On sakura
sudo tailscale up

# From htpc — verify key-only SSH onto sakura works
ssh ivokun@<sakura-tailscale-ip>
```

There is no `changeme` bootstrap password anywhere in the flow — the account
password was set interactively after `nixos-install`, and SSH has never
accepted passwords.

---

## Phase 4: Post-Installation

### Step 4.1: Restore Your Data

```bash
# Mount your backup drive
# Example:
sudo mkdir -p /mnt/backup
sudo mount /dev/sdX1 /mnt/backup

# SSH keys (htpc key already authorized during install)
cp -a /mnt/backup/arch-backup-*/ssh ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub

# GPG keys
gpg --import /mnt/backup/arch-backup-*/gnupg/*.asc 2>/dev/null

# Atuin
cp /mnt/backup/arch-backup-*/atuin-key ~/.local/share/atuin/key
# Then run: atuin login

# Neovim config — DON'T copy over HM-managed paths.
# Neovim and opencode are managed file-by-file from the flake; restore
# user-state (vim plugins state etc.) rather than raw config files.
```

### Step 4.2: Log Into the Graphical Session

SDDM is the machine's only bootstrap prompt. It greets at boot; the session
is a UWSM-managed Hyprland — do not start Hyprland manually.

```bash
# Just log in at the SDDM screen; no manual 'uwsm start hyprland' needed.
# To verify afterwards:
uwsm check is-active
```

### Step 4.2b: Verify Everything

```bash
# 1. Wayland session active (UWSM-managed Hyprland)
echo $XDG_SESSION_TYPE  # Should be "wayland"

# 2. omarchy-shell running (this is the bar/menu/launcher daemon)
pgrep -a quickshell

# 3. UWSM-managed Hyprland session unit active
systemctl --user list-units 'wayland-wm@*'

# 4. Japanese input
fcitx5-diagnose

# 5. Theme staged (Rose Pine Dawn, single-sourced in lib/palette.nix)
test -r ~/.local/state/omarchy/current/theme/colors.toml \
  -a -r ~/.local/state/omarchy/current/theme/shell.toml \
  && echo "theme staged"

# 6. zram active (50%, zstd)
zramctl

# 7. LUKS swap opened
swapon --show

# 8. Docker working
docker run hello-world

# 9. Tailscale up
tailscale status

# 10. Rebuild works
cd ~/Documents/dev/kebun
nh os switch .

# 11. No failed units or new boot warnings
systemctl --failed
systemctl --user --failed
journalctl -b -p warning

# 12. Snapper's directory is a real Btrfs subvolume
systemctl status home-snapshots-subvolume.service
sudo btrfs subvolume show /home/.snapshots

# 13. The Nix-managed OpenCode V2 wins PATH (currently pinned to 2.0.12)
# Run the stateful checks under bash even though fish is the login shell.
bash -c '
set -euo pipefail
command -v opencode
readlink -f "$(command -v opencode)"  # Must resolve into /nix/store
test "$(opencode --version)" = "opencode v2.0.12"

# Stop any pre-switch background service so the next command must start the
# newly deployed binary. Then inspect the native V2 config and local plugins.
opencode service stop || true
opencode_log="$(opencode debug paths log)/opencode.log"
if [[ -f "$opencode_log" ]]; then
  opencode_log_before=$(wc -l < "$opencode_log")
else
  opencode_log_before=0
fi
opencode debug config
opencode debug agents
# The first command starts the background service; let local plugin discovery
# finish before asserting the inventory.
sleep 2
opencode plugin list

# Both selected models must be present for the configured agents. Kimi is in
# the pinned models.dev snapshot; OpenCode Go supplies its account catalog
# dynamically. Absence here means the provider credential/catalog is not
# enabled for this account.
opencode models | grep -Fx "opencode-go/glm-5.3-flash"
opencode models | grep -Fx "kimi-for-coding/k3"

# 14. GitHub MCP reads the active github.com token from the gh keyring.
# Use a dedicated fine-grained token limited to the repositories it must read
# and read-only metadata/contents/issues/pull-request permissions. env -i stops
# accidental inheritance, but same-user processes can still query the keyring.
gh auth status --hostname github.com
opencode mcp list
# The Python NixOS server can still be starting on the first listing.
sleep 10
opencode mcp list

# Expected: all seven local servers connected. The remote Obsidian server may
# require its own authentication. Confirm the current log has no native watcher
# fallback before treating the V2 migration as deployed.
opencode_new_log=$(tail -n "+$((opencode_log_before + 1))" "$opencode_log")
grep -q "watcher started.*backend=inotify" <<<"$opencode_new_log"
! grep -q "watcher backend not supported" <<<"$opencode_new_log"
'
```

---

## Phase 5: Troubleshooting

### LUKS Not Prompting at Boot

```bash
# Boot from USB, mount system, check config
sudo cryptsetup luksDump /dev/nvme0n1p2
sudo cryptsetup luksDump /dev/nvme0n1p3
# Verify UUIDs in hosts/sakura/hardware-configuration.nix match both outputs
```

### Graphical Session / Hyprland Won't Start

```bash
# Check UWSM
uwsm check is-active || uwsm check may-start -vv

# Check shell (quickshell) logs
journalctl --user -u wayland-wm@*

# Manual start is unusual — the session is SDDM-driven. If you must:
uwsm start hyprland
```

### Rebuild Fails

```bash
# Get detailed error trace
sudo nixos-rebuild switch --flake .#sakura --show-trace

# NOTE: Do NOT reach for a blanket 'nix flake update'. If a specific pinned
# input is the culprit, update exactly that one:
#   nix flake update nixpkgs
# and read what the new pin pulls in before committing to it.

# Garbage collect if disk full
sudo nix-collect-garbage -d
```

### Network Issues

```bash
# Check iwd status
iwctl station list

# Restart iwd
sudo systemctl restart iwd

# WiFi specifically
iwctl station wlan0 scan
iwctl station wlan0 get-networks
```

---

## Quick Reference

```bash
# Rebuild system (run on sakura, from the kebun checkout there)
nh os switch .

# Update ONE pinned input (deliberate, not blanket)
nix flake update nixpkgs

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

**You're done!** Your ThinkPad X13 now runs NixOS with a fully declarative, reproducible configuration. Rebuilds run on sakura with `nh os switch .` from its checkout of this repo. Welcome to the Nix ecosystem!
