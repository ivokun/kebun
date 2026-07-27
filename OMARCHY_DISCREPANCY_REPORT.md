# Omarchy → NixOS (Kebun) Discrepancy Analysis

**Last updated:** 2026-07-27
**Sources:** live `basecamp/omarchy` (branches `master` = v3.8.4 stable, `quattro` = v4.0.0.alpha) and the research briefs in `docs/omarchy/` (`omarchy_porting.md`, `omarchy_repo.md`, `omarchy_manual.md`, `omarchy-features-guide.md`), cross-checked against the current kebun flake.

## Executive Summary

**Kebun mirrors the Omarchy v3.8.x stable stack and now reaches ~85% parity on features relevant to a single ThinkPad.** The remaining gap is dominated by **multiple/dynamic theming** (1 theme vs 19–22) plus a handful of small conveniences. Everything else that is missing is either Arch-specific plumbing (AUR, pacman), replaced by a NixOS idiom (declarative firewall, generations), or hardware/gaming features for machines and use-cases the user doesn't have.

> **Critical new context (this is the headline change since the May 2026 report):**
> Omarchy has **forked into two divergent lines**:
> - **`master` = v3.8.4 (stable, what the ISO installs today)** — the classic stack: **waybar + walker/elephant + mako + hypridle + hyprlock + swayosd**, Alacritty default, **iwd + impala**, satty. **Kebun is aligned with this line.**
> - **`quattro` = v4.0.0.alpha (default branch, in development)** — a ground-up rewrite: **Hyprland configured entirely in Lua** (`hl.*` API), a single **Quickshell** instance (`omarchy-shell`) absorbing bar/launcher/notifications/OSD/lock/clipboard/emoji, **Foot** default terminal, **NetworkManager**, **tensaku** (replaces satty), new in-house tools (`omawrite`, `omacut`, `pi` AI agent), and a **plugin system**.
>
> **Decision kebun must make explicitly:** keep tracking v3.8.x semantics (recommended for now — it's stable and already ported), while designing module boundaries so the v4 Quickshell/Lua stack can be swapped in later. `walker`, `elephant`, and `quickshell` are **all now in nixpkgs**, so a future v4 port is feasible.

---

## 1. Architecture Differences

### Omarchy (Arch-based)
- **Imperative shell scripts**: ~283 `omarchy-*` commands on v3.8 (~380 on quattro)
- **Mutable configs**: live theme switching, runtime toggles, `omarchy-reinstall-configs`
- **AUR + `yay`**: access to the Arch User Repository
- **Rolling release**: newest Hyprland (0.55+), Lua config migration underway
- **git-managed updates**: `omarchy-update` (git pull + migrations)

### Kebun (NixOS)
- **Declarative Nix expressions**: ~20 Nix modules
- **Immutable configs**: rebuild to change anything (generations = rollback)
- **nixpkgs only**: no AUR; custom derivations for the handful of Omarchy-specific tools
- **Pinned inputs**: `flake.lock` controls versions
- **Reproducible**: same config = same system

---

## 2. Component-by-Component Comparison

### 2.1 Desktop Shell Stack

| Component | Omarchy v3.8 | Omarchy v4 (quattro) | Kebun | Status vs v3.8 |
|-----------|--------------|----------------------|-------|----------------|
| Compositor | Hyprland (`.conf`) | Hyprland (**Lua** `hl.*`) | Hyprland (`.conf` via HM) | **PORTED** |
| Bar | waybar | Quickshell | waybar | **PORTED** |
| Launcher | walker + elephant | Quickshell | walker | **PORTED** |
| Notifications | mako | Quickshell | mako | **PORTED** |
| Idle / lock | hypridle + hyprlock | Quickshell | hypridle + hyprlock | **PORTED** |
| OSD | swayosd | Quickshell | swayosd | **PORTED** |
| Session | uwsm | uwsm | uwsm | **PORTED** |

**Verdict:** Kebun's shell stack matches v3.8 stable exactly. The v4 Quickshell consolidation is a future consideration, not a current gap. `quickshell` + HM `programs.quickshell` already exist in nixpkgs if kebun tracks v4 later.

### 2.2 Theme System — the primary gap

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Built-in themes | 19 (v3.8) / 22 (v4) | 1 (Rose Pine Dawn) | **PARTIAL** |
| Dynamic switching | `omarchy-theme-set` (renders `default/themed/*.tpl` from `colors.toml`) | Edit Nix + rebuild | **NOT PORTED** |
| Theme scope | GTK, Hyprland, waybar, all 4 terminals, btop, mako, swayosd, starship, tmux, obsidian, vscode, plymouth, sddm, keyboard LED | GTK, Hyprland, waybar, alacritty/ghostty/kitty, btop, mako, swayosd, starship, tmux, lazygit, helix, mpv | **PARTIAL** |
| Font switching | `omarchy-font-set` / `-list` / `-current` | Hardcoded CaskaydiaMono | **NOT PORTED** |
| Wallpaper management | per-theme `backgrounds/`, `theme-bg-next` | `menu-background` (solid colors) + swaybg | **PARTIAL** |

**Verdict — reassessed:** This is no longer "fundamentally incompatible with NixOS." `docs/omarchy/omarchy_porting.md §4.3` documents **two concrete, verified strategies**:
- **A. Declarative** — parse each `colors.toml` with `builtins.fromTOML`, a `mkTheme` function renders per-app configs, active theme = `kebun.theme = "tokyo-night"` option, switch via `home-manager switch`.
- **B. Runtime-faithful** — build all themes into the store, keep a mutable `current` symlink, a `kebun-theme-set` script flips it and reloads apps (`hyprctl reload`, `systemctl --user restart waybar`, `makoctl reload`). Preserves Omarchy's instant no-rebuild UX at the cost of one impure inode.

Still the largest single porting effort, but it is a design choice, not a wall.

### 2.3 Scripts / Commands

| Category | Omarchy v3.8 | Kebun | Notes |
|----------|--------------|-------|-------|
| Total `omarchy-*` | ~283 | ~60 | Raw count misleading — see below |
| UX helpers (screenshot, audio, brightness, battery, toggles, menus, launchers) | high | **high — near parity** | Ported 1:1 as `writeShellScriptBin` |
| `install-*` / `remove-*` (apps, gaming, services) | ~50 | 0 | **Replaced by NixOS idiom**: an "install" is a module option + rebuild |
| `pkg-*` (pacman/AUR) | 9 | 0 | No Nix meaning |
| `update-*` / `migrate` / `reinstall-*` / `refresh-*` | ~35 | `check-updates` | Replaced by `nh os switch` + generations |
| `hw-*` (per-vendor detection) | 26 | 0 | Only ThinkPad relevant; handled declaratively |
| `theme-*` / `font-*` | ~24 | 0 | See §2.2 |

**Functional user-facing script parity is high** — kebun ports the meaningful UX helpers (see §2.4) and correctly *declines* the Arch-plumbing scripts because NixOS replaces them structurally. The ~283→~60 drop is mostly install/update/pkg/hw/theme scripts that are idiom swaps, not missing features.

### 2.4 Kebun scripts covering Omarchy behaviors (ported)

Window/desktop: `window-pop`, `toggle-gaps`, `toggle-layout`, `toggle-single-window-square`, `toggle-waybar`, `toggle-nightlight`, `close-all-windows`, `cycle-monitors`, `cycle-monitor-scaling`, `toggle-laptop-display`, `toggle-mirror-display`, `color-picker`, `restart-waybar`, `restart-walker`.
Hardware/power: `brightness-toggle`, `volume-toggle`, `audio-switch`, `mic-mute`, `toggle-power-profile`, full `battery-*` family + `battery-monitor` daemon.
Capture/media: `screenshot`, `screenshot-clipboard`, `screenshot-ocr`, `screenrecord(-menu)`, `transcode`.
Launch/menus: `launch-or-focus`, `launch-tui`, `launch-{audio,wifi,bluetooth,activity,floating-terminal}`, `menu-{keybindings,capture,toggle,hardware,omarchy,background}`, `file-manager-cwd`.
Info/utility: `show-{time,battery,weather}`, `check-updates`, `localsend-share`, `reminder-{set,show,clear}`.
Dictation/a11y: `dictation-{toggle,ptt,ptt-release}` (matches Omarchy voxtype), `cursor-zoom(-reset)`.

### 2.5 Application Configs

| App | Omarchy v3.8 | Kebun | Status |
|-----|--------------|-------|--------|
| Terminals | Alacritty (default) + Ghostty + Kitty + **Foot** | Alacritty (default) + Ghostty + Kitty | **PARTIAL** (no Foot) |
| btop / fastfetch / lazygit / starship / tmux | themed | themed (Rose Pine Dawn) | **PORTED** |
| Chromium/Brave flags | Wayland ozone flags | Wayland ozone flags | **PORTED** |
| fcitx5 (IME) | mozc/Japanese | mozc/Japanese | **PORTED** |
| opencode | configured | configured (+ MCP, skills) | **PORTED** |
| Helix / mpv | (helix optional) | themed | **PORTED / ENHANCED** |
| Obsidian / xournalpp / imv | configured | obsidian ✓; xournalpp/imv via pkg | **PARTIAL** |

### 2.6 System-Level Features

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Boot loader | Limine (+ snapper-sync) | systemd-boot | **DIFFERENT (intentional)** — generations give native rollback |
| Boot splash | Plymouth (themed) | Plymouth (custom kebun theme) | **PORTED** |
| Display manager | SDDM | SDDM + auto-login | **PORTED** |
| Snapshots | Snapper (btrfs) | Snapper (`/home` only) | **PORTED** |
| ZRAM | zram-generator | `zramSwap` (NixOS) | **PORTED** |
| Encryption | LUKS + FIDO2/fingerprint setup | LUKS2 + TPM2 + fingerprint | **ENHANCED / PARTIAL** (no FIDO2 sudo/polkit) |
| Wi-Fi | iwd + impala (v3.8) | iwd + impala | **PORTED** |
| Firewall | ufw | nftables (declarative) | **DIFFERENT (idiom swap)** |
| Printing | CUPS | CUPS + gutenprint/hplip + avahi | **PORTED** |
| Hibernation | `omarchy-hibernation-setup` | Suspend only (no hibernate) | **NOT PORTED** |
| Docker | enabled | enabled + autoprune | **PORTED** |

### 2.7 Hardware Support

Only ThinkPad X13 (user's machine) is relevant. Omarchy's ~26 `hw-*` scripts and the ASUS/Dell/Framework/Surface/Apple-T2/Intel-PTL/NVIDIA driver stacks are **irrelevant** for this host. Kebun covers AMD Renoir (amdgpu), TPM2, fingerprint, s0ix resume quirks, and lid/power behavior declaratively. **Effective parity for this hardware: 100%.**

### 2.8 AI / Modern additions

| Feature | Omarchy | Kebun | Status |
|---------|---------|-------|--------|
| Voice dictation | voxtype | hyprwhspr-rs + `dictation-*` scripts | **PORTED (equivalent)** |
| Coding agents | claude-code, opencode | claude-code, opencode | **PORTED** |
| `pi` AI agent (v4) | quattro only | — | N/A (v4) |
| Japanese proofreading | tensaku (v4) | — | **NOT PORTED** (relevant: user runs fcitx5-mozc) |
| Web apps as first-class | curated PWA `.desktop` set + `launch-or-focus-webapp` | `web2app` fish helper only | **PARTIAL** |
| Plugin system | quattro only | — | N/A (v4) |

---

## 3. Remaining Gaps, Ranked

### Real, portable, worth doing
1. **Multiple themes + switching** — biggest effort; two concrete strategies in `docs/omarchy/omarchy_porting.md §4.3`. Start with 3–4 palettes via strategy A (declarative `mkTheme`).
2. **Web-app PWA system** — curated launchers (HEY/ChatGPT/etc.) via HM `xdg.desktopEntries` + a `launch-or-focus-webapp` script. Trivially declarative; real daily value.
3. **Font switching** (`omarchy-font-set` equivalent) — small; needs the theme-module machinery from #1 to be worthwhile.
4. **Hibernation** — `omarchy-hibernation-*` behavior via NixOS `boot.resumeDevice` + swapfile resume. Verify current suspend-only setup is intentional.

### Intentional / irrelevant — do NOT chase
- Gaming suite (Steam/Lutris/Heroic/RetroArch/etc.) — absent by choice
- Per-vendor `hw-*` (ASUS/Dell/Framework/Surface/Apple/Intel-PTL) — wrong hardware
- Limine bootloader — systemd-boot + generations is the deliberate NixOS choice
- `foot` terminal — three terminals already configured
- AUR/`pkg-*`/`update-*`/`refresh-*`/`reinstall-*` scripts — replaced by `nh os switch` + generations

### Future (only if kebun decides to track Omarchy 4)
- Quickshell shell (replaces waybar+walker+mako+swayosd+hypridle+hyprlock) — `quickshell` in nixpkgs
- Lua Hyprland config — HM supports Lua config since 26.05
- NetworkManager (from iwd), Foot default, tensaku, omawrite/omacut, plugin system

---

## 4. Missing-from-nixpkgs (need custom derivation or idiom swap)

Per `docs/omarchy/omarchy_porting.md §2.8`: `tensaku`, `omawrite`, `omacut` (v4 tools), `aether`, `asdcontrol`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `tobi-try`, `elephant-1password` (and other elephant providers). Idiom swaps (no package needed): `ufw`→`networking.firewall`, `system-config-printer`→CUPS web UI, `omarchy-chromium`→`chromium` + flags, `omarchy-nvim`→own nvim config, `ttf-ia-writer`→`ia-writer-*` attrs. Everything user-facing in the v3.8 stack (incl. `walker` 2.17, `elephant` 2.22, `quickshell`) is already in nixpkgs.

---

## 5. Prior Art (reusable)

- **henrysipp/omarchy-nix** (729★, unmaintained) — full NixOS+HM module reimplementation; best skeleton for a `kebun.omarchy { theme; ... }` option set.
- **Jylhis/marchyo** (active) — feature-flag module architecture.
- **richardgill/nix** — "thin Nix layer over plain config files" philosophy (good for tracking upstream conf).
- Omarchy Discussion #987 — running HM on top of Arch Omarchy (hybrid escape hatch).

Full list with URLs in `docs/omarchy/omarchy_porting.md §3`.

---

## 6. Summary Statistics (vs v3.8 stable)

| Category | Assessment |
|----------|------------|
| Desktop shell stack | **100%** (matches v3.8 exactly) |
| Theme system | **~20%** (1 theme, no switching/font-set) — primary gap |
| UX scripts | **~90%** of meaningful helpers; Arch-plumbing scripts correctly declined |
| App configs | **~85%** (missing Foot; xournalpp/imv unthemed) |
| System features | **~90%** (missing hibernation; Limine/firewall are intentional swaps) |
| Hardware (this ThinkPad) | **100%** |
| AI / modern | **~80%** (dictation + agents ported; web-apps partial; tensaku absent) |
| **Overall (relevant features)** | **~85%** |

**Bottom line:** Kebun is a faithful, stable-aligned port of Omarchy v3.8. Close the theme gap (§3 #1) and the web-app gap (§3 #2) and it reaches near-complete parity for this machine. Treat Omarchy 4 (Quickshell + Lua) as a deliberate future migration, not a backlog of missing features.
