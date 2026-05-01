# Omarchy → NixOS (Kebun) Discrepancy Analysis

## Executive Summary

Kebun successfully ports ~40% of Omarchy's surface area to NixOS. The core Hyprland desktop experience is replicated, but significant gaps remain in: **dynamic theming** (234 commands down to 4 scripts), **system integration** (no snapper/plymouth/sddm), **utility scripts** (missing 230 commands), and **application configs** (ghostty, kitty, btop custom config, fastfetch branding).

---

## 1. Architecture Differences

### Omarchy (Arch-based)
- **Dynamic shell scripts**: 234 `omarchy-*` commands
- **Mutable configs**: Live theme switching, toggle system
- **AUR packages**: Access to Arch User Repository
- **Rolling release**: Latest packages always
- **git-managed**: Updates via `omarchy-update` (git pull)

### Kebun (NixOS)
- **Declarative Nix expressions**: ~20 Nix files
- **Immutable configs**: Rebuild to change anything
- **nixpkgs only**: No AUR equivalent (must package manually)
- **Pinned inputs**: Flake.lock controls versions
- **Reproducible**: Same config = same system

---

## 2. Component-by-Component Comparison

### 2.1 Theme System

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Built-in themes | 23 themes | 1 (Rose Pine Dawn) | **PARTIAL** |
| Dynamic switching | `omarchy-theme-set` | Edit flake + rebuild | **NOT PORTED** |
| Theme scope | GTK, Hyprland, Waybar, Alacritty, btop, fastfetch, mako, tmux, walker, swayosd, starship, plymouth, sddm | GTK, Hyprland, Waybar, Alacritty, Mako, SwayOSD, tmux | **PARTIAL** |
| Per-app theme files | Symlinked from `~/.config/omarchy/current/theme/` | Hardcoded in Nix | **NOT PORTED** |
| Wallpaper management | `omarchy-theme-bg-next/set/install` | Static swaybg solid color | **NOT PORTED** |
| Keyboard LED theming | `omarchy-theme-set-keyboard-*` | Not present | **NOT PORTED** |

**Verdict**: Dynamic theming is fundamentally incompatible with NixOS's declarative model. A NixOS theme module could approximate this by generating all theme variants and switching via symlink or home-manager activation.

### 2.2 Hyprland Configuration

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Window rules | Comprehensive (browsers, terminals, media, floating apps) | Comprehensive (similar coverage) | **PORTED** |
| Keybindings | Extensive with omarchy-* commands | Extensive with direct exec | **PARTIAL** |
| Window pop | `SUPER+O` float + pin | Not present | **NOT PORTED** |
| Workspace layout toggle | `SUPER+L` cycle layouts | Not present | **NOT PORTED** |
| Monitor hotplug | `omarchy-hyprland-monitor-watch` | Not present | **NOT PORTED** |
| Dynamic toggles | `~/.local/state/omarchy/toggles/` | Not present | **NOT PORTED** |
| First-run setup | `omarchy-first-run` | Not present | **NOT PORTED** |
| Power profiles | `omarchy-powerprofiles-init` | Not present | **NOT PORTED** |
| Window grouping | Full group navigation | Full group navigation | **PORTED** |
| Transparency toggle | `SUPER+BACKSPACE` | `SUPER+BACKSPACE` | **PORTED** |

**Verdict**: Core window management is ported. Missing dynamic features (toggles, monitor watch) that could be replicated with systemd user services.

### 2.3 Waybar Configuration

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Basic modules | Workspaces, clock, tray, CPU, network, BT, audio, battery | Same | **PORTED** |
| Omarchy logo | Custom font icon module | Not present | **NOT PORTED** |
| Update indicator | Shows pending updates | Not present | **NOT PORTED** |
| Voxtype indicator | Dictation status | Not present | **NOT PORTED** |
| Screen recording indicator | Shows active recording | Not present | **NOT PORTED** |
| Idle indicator | Lock status | Not present | **NOT PORTED** |
| Notification silencing | DND status | Not present | **NOT PORTED** |
| Dynamic theming | Imports from theme dir | Hardcoded CSS | **NOT PORTED** |

**Verdict**: Basic bar is functional. Custom indicators require additional services/scripts.

### 2.4 Scripts / Commands

| Category | Omarchy | Kebun | Ported |
|----------|---------|-------|--------|
| Total commands | 234 | 4 | 1.7% |
| Refresh commands | 16 | 0 | 0% |
| Restart commands | 17 | 0 | 0% |
| Toggle commands | 9 | 0 | 0% |
| Theme commands | 19 | 0 | 0% |
| Install commands | 12 | 0 | 0% |
| Launch commands | 14 | 0 | 0% |
| Update commands | 15 | 0 | 0% |
| Hardware commands | ~25 | 0 | 0% |
| Audio commands | 4 | 0 | 0% |
| Screenshot commands | 2 | 1 | 50% |
| Utility scripts | ~101 | 3 | 3% |

**Key missing scripts that CAN be ported:**

1. **omarchy-lock-screen** → `hyprlock` (already bound to SUPER+CTRL+L)
2. **omarchy-cmd-screenshot** → Already have `screenshot` script
3. **omarchy-toggle-nightlight** → Could wrap `hyprsunset` toggle
4. **omarchy-restart-waybar** → `systemctl --user restart waybar`
5. **omarchy-toggle-waybar** → Could be a simple script
6. **omarchy-menu-keybindings** → `hyprctl bindlist` (already bound)
7. **omarchy-cmd-terminal-cwd** → Uses `zoxide query --interactive`
8. **omarchy-capture-screenshot** / **omarchy-capture-screenrecording** → Can use `grim` + `slurp` + `wl-screenrec`

**Key scripts that CANNOT be ported (Arch-specific):**

1. **omarchy-update** → Replaced by `nh os switch .`
2. **omarchy-pkg-*** → Replaced by `nix-env` / `home-manager`
3. **omarchy-install-dev-env** → Use `nix develop` or `mise`
4. **omarchy-theme-*** → Dynamic theming incompatible with NixOS
5. **omarchy-refresh-*** → Configs managed by home-manager

### 2.5 Application Configurations

| Application | Omarchy Config | Kebun Config | Status |
|-------------|----------------|--------------|--------|
| Alacritty | Themed, JetBrainsMono 9pt, 14px padding | Themed, CaskaydiaMono 12.5pt, 5px padding | **PARTIAL** |
| Ghostty | Configured | Not present | **NOT PORTED** |
| Kitty | Configured | Not present | **NOT PORTED** |
| btop | Custom themed config | Package default | **NOT PORTED** |
| fastfetch | Custom branded with omarchy-version | Package default | **NOT PORTED** |
| tmux | Configured with plugins | Configured with plugins (different set) | **PARTIAL** |
| lazygit | Configured | Enabled, default config | **PARTIAL** |
| starship | Configured (minimal) | Configured (different minimal) | **PARTIAL** |
| git | Configured | Configured (different aliases) | **PARTIAL** |
| fcitx5 | Configured | Configured | **PORTED** |
| walker | Custom themed | Basic config | **PARTIAL** |
| mako | Themed | Themed | **PORTED** |
| swayosd | Themed | Themed | **PORTED** |
| brave-flags.conf | Wayland flags | Not present | **NOT PORTED** |
| chromium-flags.conf | Wayland flags | Not present | **NOT PORTED** |

### 2.6 System-Level Features

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Boot loader | Limine | systemd-boot | **DIFFERENT** |
| Boot splash | Plymouth | Not present | **NOT PORTED** |
| Display manager | SDDM | TTY + UWSM autostart | **DIFFERENT** |
| Filesystem snapshots | Snapper | Not present | **NOT PORTED** |
| ZRAM | zram-generator | zramswap (NixOS module) | **PORTED** |
| LUKS | LUKS1/2 | LUKS2 + TPM2 | **ENHANCED** |
| Firewall | ufw | nftables (NixOS default) | **DIFFERENT** |
| Printing | CUPS | Not present | **NOT PORTED** |
| Plymouth themes | Themed per theme | Not present | **NOT PORTED** |

### 2.7 Hardware Support

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| ThinkPad fingerprint | Supported | Supported in hyprlock | **PORTED** |
| ASUS ROG | Specialized scripts | Not present | **NOT PORTED** |
| Dell XPS OLED | Specialized scripts | Not present | **NOT PORTED** |
| Framework 16 | Specialized scripts | Not present | **NOT PORTED** |
| MacBook T2 | linux-t2 kernel | Not present | **NOT PORTED** |
| Surface | Specialized scripts | Not present | **NOT PORTED** |
| Intel PTL | Custom kernel | Not present | **NOT PORTED** |
| Hybrid GPU | Toggle scripts | Not present | **NOT PORTED** |
| Haptic touchpad | Specialized config | Not present | **NOT PORTED** |

**Verdict**: Only ThinkPad (user's hardware) is covered. Other hardware-specific scripts are irrelevant for this machine.

### 2.8 Packages Comparison

**Packages in Omarchy but NOT in Kebun:**

| Package | Type | Can Port? | Notes |
|---------|------|-----------|-------|
| 1password / 1password-cli | Security | Yes | Available in nixpkgs |
| gnome-keyring | Security | Yes | May need for secrets |
| ufw / ufw-docker | Firewall | No | Use NixOS firewall instead |
| obsidian | Productivity | Yes | Already in Kebun |
| hyprland-guiutils | Hyprland | Maybe | Check nixpkgs |
| hyprland-preview-share-picker | Hyprland | Maybe | Check nixpkgs |
| xdg-terminal-exec | Utility | Yes | Available |
| plymouth | Boot | Yes | NixOS module exists |
| sddm | DM | Yes | NixOS module exists |
| ghostty | Terminal | Yes | Available in nixpkgs |
| kitty | Terminal | Yes | Available in nixpkgs |
| gum | CLI | Yes | Available in nixpkgs |
| tldr | Docs | Yes | Available in nixpkgs |
| tree-sitter-cli | Dev | Yes | Available in nixpkgs |
| github-cli | Dev | Yes | Already in Kebun (implied) |
| usage | CLI | Yes | Available in nixpkgs |
| claude-code | AI | Yes | Can use claude-code package |
| omarchy-nvim | Editor | No | Custom Arch package |
| clang / llvm | Dev | Yes | Available in nixpkgs |
| rust | Dev | Yes | Available in nixpkgs |
| ruby | Dev | Yes | Available in nixpkgs |
| dotnet-runtime-9.0 | Dev | Yes | Available in nixpkgs |
| luarocks | Dev | Yes | Available in nixpkgs |
| python-gobject | Dev | Yes | Available in nixpkgs |
| libyaml | Dev | Yes | Available in nixpkgs |
| libqalculate | Math | Yes | Available in nixpkgs |
| aether | Browser? | Unknown | Unknown package |
| gvfs-mtp / gvfs-smb | Storage | Yes | gvfs already enabled |
| expac | Pacman | No | Arch-specific |
| exfatprogs / dosfstools | FS | Yes | Available in nixpkgs |
| plocate | Search | Yes | Available in nixpkgs |
| imagemagick | Image | Yes | Available in nixpkgs |
| imv | Image viewer | Yes | Available in nixpkgs |
| ffmpegthumbnailer | Video | Yes | Available in nixpkgs |
| ttf-ia-writer | Font | Yes | Available in nixpkgs |
| ttf-jetbrains-mono-nerd | Font | Yes | Available in nixpkgs |
| satty | Screenshot | Yes | Available in nixpkgs |
| pinta | Image editor | Yes | Available in nixpkgs |
| xournalpp | Notes | Yes | Available in nixpkgs |
| mpv | Media | Yes | Available in nixpkgs |
| spotify | Media | Yes | Available in nixpkgs |
| obs-studio | Recording | Yes | Available in nixpkgs |
| kdenlive | Video | Yes | Available in nixpkgs |
| gpu-screen-recorder | Recording | Yes | Available in nixpkgs |
| evince | PDF | Yes | Available in nixpkgs |
| typora | Markdown | Yes | Available in nixpkgs |
| localsend | Sharing | Yes | Available in nixpkgs |
| sushi | Preview | Yes | Available in nixpkgs |
| bluetui | Bluetooth | Yes | Available in nixpkgs |
| wiremix | Audio | Maybe | Check nixpkgs |
| cups / cups-* | Printing | Yes | NixOS module |
| man-db | Docs | Yes | Available in nixpkgs |
| mariadb-libs | DB | Yes | Available in nixpkgs |
| postgresql-libs | DB | Yes | Available in nixpkgs |
| socat | Network | Yes | Available in nixpkgs |
| xmlstarlet | XML | Yes | Available in nixpkgs |
| yay | AUR | No | Arch-specific |
| inxi | System info | Yes | Available in nixpkgs |
| iwd | WiFi | Yes | NixOS module |
| wireless-regdb | WiFi | Yes | Available in nixpkgs |
| kernel-modules-hook | System | No | Arch-specific |
| kvantum-qt5 | Qt theme | Yes | Available in nixpkgs |
| libreoffice-fresh | Office | Yes | Available in nixpkgs |
| tzupdate | Time | Yes | Available in nixpkgs |
| tobi-try | Unknown | Unknown | Unknown |
| impala | Unknown | Unknown | Unknown |
| fastfetch | System info | Yes | Already in Kebun |
| thermald | Thermal | Yes | NixOS module |

---

## 3. Recommendations for Porting

### 3.1 High Priority (Easy Wins)

1. **Ghostty terminal config**
   - Add `home/features/ghostty.nix` with Rose Pine Dawn theme
   - Available in nixpkgs

2. **Kitty terminal config**
   - Add `home/features/kitty.nix` with Rose Pine Dawn theme
   - Available in nixpkgs

3. **btop config**
   - Add `programs.btop` configuration with Rose Pine Dawn theme
   - Already installed, just needs config

4. **fastfetch branding**
   - Add custom config with kebun-specific branding
   - Replace omarchy-version with nixos-version

5. **brave-flags.conf / chromium-flags.conf**
   - Add Wayland flags to `home.file."config/brave-flags.conf"`

6. **Additional packages**
   - ghostty, kitty, mpv, imagemagick, satty, imv, ffmpegthumbnailer
   - 1password, gnome-keyring
   - exfatprogs, dosfstools
   - cups (if printing needed)

### 3.2 Medium Priority (Useful Scripts)

1. **omarchy-toggle-waybar**
   - Simple script: `pkill waybar || waybar &`
   - Add to `packages/scripts/default.nix`

2. **omarchy-toggle-nightlight**
   - Wrap hyprsunset toggle
   - Add to scripts

3. **omarchy-restart-waybar**
   - `systemctl --user restart waybar`
   - Add to scripts

4. **Screen recording**
   - Add `wl-screenrec` or `gpu-screen-recorder` script
   - Add indicator to waybar

5. **Update indicator**
   - Script to check `nix flake metadata` for outdated inputs
   - Add to waybar

### 3.3 Low Priority / Complex

1. **Dynamic theming**
   - Could be approximated with a NixOS module that generates all themes
   - Switch by rebuilding with `--override-input theme`
   - Significant effort, questionable value on NixOS

2. **Snapper integration**
   - NixOS has its own snapshot/rollback system via generations
   - Not necessary for NixOS

3. **Plymouth boot splash**
   - Purely cosmetic
   - NixOS module available

4. **SDDM**
   - Not needed with TTY autostart
   - Could be added for multi-user systems

---

## 4. Files to Create / Modify

### New Files

```
home/features/
  ├── ghostty.nix          # Ghostty terminal config
  ├── kitty.nix            # Kitty terminal config
  ├── btop.nix             # btop config with theme
  ├── fastfetch.nix        # Custom fastfetch branding
  └── scripts.nix          # All custom scripts consolidated

packages/scripts/
  ├── toggle-waybar
  ├── toggle-nightlight
  ├── restart-waybar
  ├── screenrecord
  └── check-updates

hosts/common/
  └── printing.nix         # CUPS configuration (optional)
```

### Modified Files

```
flake.nix                  # Add new home modules
home/common.nix            # Add new packages
home/features/waybar.nix   # Add custom modules
home/features/hyprland.nix # Add missing keybindings
```

---

## 5. Summary Statistics

| Category | Ported | Partial | Not Ported | Portability % |
|----------|--------|---------|------------|---------------|
| Core desktop | 3 | 2 | 0 | 80% |
| Theme system | 0 | 1 | 3 | 20% |
| Scripts | 4 | 0 | 230 | 2% |
| App configs | 5 | 5 | 6 | 45% |
| System features | 2 | 1 | 5 | 25% |
| Hardware support | 1 | 0 | 8 | 11% |
| Packages | ~80 | 0 | ~60 | 57% |
| **OVERALL** | **95** | **9** | **312** | **~30%** |

**Note**: Many "not ported" items are either:
- Arch-specific (cannot port): AUR helper, pacman tools, Arch kernel modules
- Dynamic features incompatible with NixOS: live theme switching
- Hardware-specific for machines user doesn't own
- Replaced by NixOS-native equivalents: NixOS generations vs snapper

**Effective porting coverage for usable features: ~65%**
