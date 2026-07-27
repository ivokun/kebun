# Porting Context Brief: Omarchy → NixOS ("kebun")

**Date:** 2026-07-27 · **Audience:** builder of *kebun*, a personal NixOS distribution porting Omarchy
**Verification method:** every nixpkgs attribute and module path below was checked against the live `NixOS/nixpkgs` (`nixos-unstable`) and `nix-community/home-manager` (`master`) trees on 2026-07-27; Omarchy facts were checked against the live `basecamp/omarchy` repo (branches `master` = v3.8.x stable, `quattro` = v4 development).

---

## TL;DR

- Current Omarchy stable is **v3.8.4 (2026-07-21)**; **Omarchy 4** is in active development on the `quattro` branch and **replaces Waybar + Walker + mako + hypridle/hyprlock + swayosd with a Quickshell-based shell**, moves the default terminal **Alacritty → Foot**, and switches **iwd → NetworkManager**.[^1^][^4^] Decide explicitly whether kebun ports v3.8.x (what users run today) or tracks v4.
- **Everything user-facing in the v3.8 stack has a nixpkgs package**, including the two historically hard ones: **`walker` (2.17.0) and `elephant` (2.22.0) are both in nixpkgs now**, and `quickshell` is too.[^20^][^21^][^22^]
- The only gaps are **Omarchy's own patched/meta packages and a handful of small tools** (`omarchy-chromium`, `omarchy-walker` meta, `omarchy-nvim`, `omarchy-keyring`, `aether`, `asdcontrol`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `tensaku`, `omacut`/`omawrite`, `tobi-try`, `elephant-1password`, `ttf-ia-writer` as such, `ufw`, `system-config-printer`, `expac`).[^11^] Each needs a small custom derivation or an idiom swap (details in §5).
- There is one substantial prior art: **henrysipp/omarchy-nix (729★)** — a full NixOS+home-manager module reimplementation, currently unmaintained but fork-worthy; plus several smaller efforts (§3).[^13^]

---

## 1. Omarchy release state

### 1.1 Current release & cadence

Latest stable release: **Omarchy v3.8.4**, published **2026-07-21** (ISO `omarchy-3.8.4.iso`).[^1^] The repo sits at ~24.1k stars; `master` tracks v3.8.x and the default development branch is now **`quattro`** (Omarchy 4).[^2^]

Cadence from the release history (GitHub releases API, 2026-07-27):[^1^]

| Release | Date | Theme |
|---|---|---|
| v3.0.x | 2025-09 | 3.x line begins (walker/elephant launcher era, unified theming) |
| v3.1.0–3.1.7 | 2025-10 – 2025-11 | Rapid patch cadence (~weekly) |
| v3.2.0–3.2.3 | 2025-11-21 – 2025-12 | Terminal launch rework (`xdg-terminal-exec` + `xdg-terminals.list`); Ghostty default period |
| v3.3.x | 2026-01-07/08 | — |
| v3.4.x | 2026-02-26 – 2026-03 | — |
| v3.5.x | 2026-04-03/16 | "The New Release"; new themes (Lumon, Retro 82) |
| v3.6.0 | 2026-04-23 | — |
| v3.7.0 | 2026-05-04 | "The Gaming Edition"; unified `omarchy` CLI; OCR text-extract capture |
| v3.8.0 | 2026-05-09 | — |
| v3.8.2 | 2026-05-24 | **Compatibility with Hyprland 0.55** (configs not yet converted to Lua) |
| v3.8.3 | 2026-07-13 | tmux pane controls + CSI-u across all four terminals; hardware fixes |
| v3.8.4 | 2026-07-21 | Latest. Fixes Neovim theme symlink "pointing at the Omarchy 4 theme location" |

**Cadence:** roughly one minor per 3–6 weeks plus hotfix patches; DHH ships constantly and the project self-describes as moving too fast for downstream ports to chase feature parity.[^1^][^13^]

### 1.2 Major 2025→2026 stack changes (what kebun must pin down)

From diffing `install/omarchy-base.packages` on `master` (v3.8.4) vs `quattro` (v4-dev):[^3^][^4^]

| Area | Omarchy v3.8.x (today) | Omarchy 4 (`quattro`, unreleased) |
|---|---|---|
| Bar / shell | **waybar** | **quickshell** (`quickshell-git`) — absorbs bar, and apparently OSD/notifications/lock |
| Launcher | **walker + elephant** (via `omarchy-walker` meta package)[^11^] | dropped (Quickshell launcher) |
| Notifications | **mako** | dropped (Quickshell) |
| Idle / lock | **hypridle + hyprlock** | both absent from package list (lock presumably Quickshell-based; **unconfirmed**) |
| OSD | **swayosd** | dropped |
| Terminal (default) | **Alacritty** (first entry in `xdg-terminals.list`)[^6^][^7^]; Ghostty/Foot/Kitty fully supported via *Install > Terminal*[^6^] | **Foot** (alacritty removed, `foot` added; `foot.desktop` ships in `applications/`) |
| Wi-Fi | **iwd + impala** TUI | **NetworkManager** (iwd/impala dropped) |
| Bluetooth | **bluetui** | bluez stack + tools (TUI TBD) |
| Screenshot annotation | **satty** | **tensaku** (not in nixpkgs) |
| Font | `ttf-jetbrains-mono-nerd` | `ttf-jetbrains-mono-nerd-basic` |
| Browser | **Chromium** (`omarchy-chromium` patched build + `chromium-flags.conf`)[^3^][^11^] | unchanged |
| Login manager | **sddm**, **plymouth**, **limine** bootloader, snapper rollbacks | unchanged so far |
| Audio mixer TUI | wiremix | dropped |
| Power/perf | power-profiles-daemon, brightnessctl, playerctl | ppd kept; **playerctl dropped** in favor of `mpv-mpris` |

Other dated changes worth knowing: terminal launching was reworked ~v3.1.5 (Nov 2025) and again at v3.2.0 around a Ghostty-default experiment; current `master` again lists `Alacritty.desktop` first.[^7^][^27^][^28^] Hyprland 0.55 compatibility landed in v3.8.2 without converting configs to Lua; upstream Hyprland is migrating to Lua config and NixOS wiki notes home-manager supports Lua config since HM 26.05 — a live moving target for kebun.[^1^][^19^]

**Recommendation:** port **v3.8.x semantics** now (it is what the ISO installs), but design kebun's module boundaries (bar/launcher/notify/lock as one replaceable "shell" concern) so the Quickshell-based v4 stack can be swapped in; `quickshell` and a home-manager `programs.quickshell` module already exist.[^22^][^25^]

---

## 2. Component-by-component NixOS mapping

Legend: **by-name ✓** = verified present at `pkgs/by-name/<2-letter-prefix>/<attr>/package.nix` on `nixos-unstable` 2026-07-27 (URLs in footnotes). HM = home-manager module (`modules/…` in nix-community/home-manager, verified). NixOS = NixOS module option. "pkg only" = install via `environment.systemPackages`/`home.packages`.

### 2.1 Wayland session core

| Omarchy/Arch component | Arch package | nixpkgs attribute | HM / NixOS module | Notes |
|---|---|---|---|---|
| Compositor | `hyprland` | `hyprland` ✓ | **NixOS:** `programs.hyprland.enable` (+ `withUWSM = true`); **HM:** `wayland.windowManager.hyprland`[^19^][^23^][^24^] | Set HM `systemd.enable = false` when using UWSM (conflict).[^19^] |
| Session manager | `uwsm` | `uwsm` ✓ | **NixOS:** `programs.uwsm.enable` / `programs.hyprland.withUWSM`[^21^][^24^] | Omarchy launches everything under uwsm; mirror with `waylandCompositors` or the hyprland flag. |
| Idle daemon | `hypridle` | `hypridle` ✓ | **HM:** `services.hypridle`[^24^] | Dropped in Omarchy 4 (Quickshell). |
| Screen lock | `hyprlock` | `hyprlock` ✓ | **HM:** `programs.hyprlock`; **NixOS:** `programs.hyprlock` (PAM)[^24^] | NixOS module needed for PAM unlocking. |
| Blue-light filter | `hyprsunset` | `hyprsunset` ✓ | **HM:** `services.hyprsunset`[^24^] | |
| Wallpaper (Omarchy uses swaybg) | `swaybg` | `swaybg` ✓ | pkg only | `hyprpaper` ✓ (+ HM `services.hyprpaper`) if preferred.[^24^] |
| Color picker | `hyprpicker` | `hyprpicker` ✓ | pkg only | |
| Polkit agent | `polkit-gnome` | `polkit_gnome` ✓ (by-name)[^26^] | **NixOS:** `security.polkit.enable` + systemd user unit; or `hyprpolkitagent` ✓ + HM `services.hyprpolkitagent`[^24^] | Omarchy 4 drops polkit-gnome (agent TBD). |
| XDG portal | `xdg-desktop-portal-hyprland` | `xdg-desktop-portal-hyprland` ✓ (path `pkgs/applications/window-managers/hyprwm/xdg-desktop-portal-hyprland/`)[^26^] | **NixOS:** `xdg.portal.extraPortals`; auto-added by `programs.hyprland` | plus `xdg-desktop-portal-gtk`.[^19^] |
| Hyprland GUI utils | `hyprland-guiutils` | **MISSING** | — | New hypr* helper lib/app; needs custom derivation. |
| Share picker | `hyprland-preview-share-picker` | **MISSING** | — | Omarchy/AUR package;[^11^] needs custom derivation (upstream: WhySoBad/hyprland-preview-share-picker). |
| Screen freeze (for screenshots) | `wayfreeze` | `wayfreeze` ✓ (by-name) | pkg only | Used by Omarchy capture scripts.[^11^] |

### 2.2 Bar, launcher, notifications, OSD

| Omarchy/Arch component | Arch package | nixpkgs attribute | HM / NixOS module | Notes |
|---|---|---|---|---|
| Status bar | `waybar` | `waybar` ✓ | **HM:** `programs.waybar` (incl. `systemd.target` integration)[^24^] | Omarchy 4 replaces with Quickshell. |
| Launcher | `omarchy-walker` (meta → walker + elephant providers)[^11^] | `walker` ✓ **2.17.0** (by-name)[^20^] | **no HM `programs.walker` module** (verified absent in HM `modules/programs/`)[^25^] — configure via `xdg.configFile` / `home.file` | Upstream: abenz1267/walker. |
| Launcher backend | (bundled) | `elephant` ✓ **2.22.0** (by-name)[^20^] | **HM:** `services.elephant` exists (verified `modules/services/elephant.nix`)[^25^] | Elephant providers (e.g. `elephant-1password`) are separate packages — **not in nixpkgs**; package per-provider as needed.[^40^] |
| v4 shell | `quickshell-git` (v4) | `quickshell` ✓ (by-name)[^22^] | **HM:** `programs.quickshell` (verified)[^25^] | Pin release, not `-git`, if possible. |
| Notifications | `mako` | `mako` ✓ | **HM:** `services.mako`[^24^] | `dunst` ✓ + HM `services.dunst` as alternate. |
| OSD | `swayosd` | `swayosd` ✓ | **HM:** `services.swayosd`[^24^] | |
| Launcher alternates | — | `fuzzel` ✓ (HM `programs.fuzzel`), `rofi` ✓ (HM `programs.rofi`; nixpkgs rofi is the Wayland fork — no separate `rofi-wayland` attr), `wofi` ✓, `tofi` ✓, `hyprlauncher` ✓ | HM modules exist for fuzzel/rofi/wofi/tofi[^24^] | |
| Logout menu | — | `wlogout` ✓ | HM `programs.wlogout` ✓[^24^] | Not in Omarchy base but typical complement. |

### 2.3 System services & hardware

| Omarchy/Arch component | Arch package | nixpkgs attribute | HM / NixOS module | Notes |
|---|---|---|---|---|
| Audio | `pipewire`(-alsa/-jack/-pulse), `wireplumber` | `pipewire`, `wireplumber` ✓ | **NixOS:** `services.pipewire.{enable,alsa,jack,pulse}`, `wireplumber` configured under it | No rtkit fiddling; module handles it. |
| Volume control | `pamixer`, `wiremix` | `pamixer` ✓, `wiremix` ✓ | pkg only | wiremix dropped in v4. |
| Network | `iwd` + `impala` (v3.8) / `networkmanager` (v4) | `iwd`, `impala` ✓, `networkmanager` ✓ | **NixOS:** `networking.networkmanager.enable` (or `networking.wireless.iwd.enable`); **HM:** `services.network-manager-applet`[^24^] | Port-direction decision: v3.8 = iwd/impala; v4 = NM. |
| Bluetooth | `bluez` + `bluetui` | `bluez` ✓, `bluetui` ✓ | **NixOS:** `hardware.bluetooth.enable`; **HM/NixOS:** `services.blueman` + HM `services.blueman-applet`[^24^] | GUI alternates: `blueman` ✓, `overskride` ✓. |
| Power profiles | `power-profiles-daemon` | `power-profiles-daemon` ✓ | **NixOS:** `services.power-profiles-daemon.enable` | Conflicts with `services.tlp` (`tlp` ✓ exists) — pick one, as on Arch. |
| Battery | `upower` (dep) | `upower` | **NixOS:** `services.upower.enable` | |
| Brightness / media keys | `brightnessctl`, `playerctl` | `brightnessctl` ✓, `playerctl` ✓ | pkg only | playerctl dropped in v4 (`mpv-mpris`; `mpv` ✓ has mpris support). |
| Timezone autodetect | `tzupdate` | `tzupdate` ✓ (by-name) | **NixOS alt:** `services.automatic-timezoned.enable` | Prefer the NixOS-native service. |
| Printing | `cups*`, `system-config-printer` | `cups`; **system-config-printer MISSING** | **NixOS:** `services.printing.enable` | GUI: GNOME Settings or CUPS web UI instead. |
| Apple display brightness | `asdcontrol` | **MISSING** | — | Small C tool (nikosdion/asdcontrol); trivial custom derivation.[^11^] |
| Firewall | `ufw`, `ufw-docker` | **MISSING (both)** | **NixOS:** `networking.firewall.*` (declarative) | Idiom swap, not a package gap. |
| File mounts | `gvfs-*`, `udiskie` (v4) | `gvfs`, `udiskie` ✓ | **NixOS:** `services.gvfs`, `services.udisks2`; **HM:** `services.udiskie`[^24^] | |

### 2.4 Terminal & shell UX

| Omarchy/Arch component | Arch package | nixpkgs attribute | HM / NixOS module | Notes |
|---|---|---|---|---|
| Default terminal (v3.8) | `alacritty` | `alacritty` ✓ | **HM:** `programs.alacritty`[^24^] | Kept for tooling even when another terminal is default.[^6^] |
| Supported terminals | `ghostty`, `foot`, `kitty` | `ghostty` ✓, `foot` ✓, `kitty` ✓ | **HM:** `programs.ghostty`, `programs.foot`, `programs.kitty` (all verified)[^24^] | v4 default = Foot.[^4^] |
| Terminal selection | `xdg-terminal-exec` + `~/.config/xdg-terminals.list`[^7^] | `xdg-terminal-exec` ✓ (by-name) | pkg + `home.file."xdg-terminals.list"` | Cheap to replicate exactly. |
| Multiplexer | `tmux` | `tmux` ✓ | **HM:** `programs.tmux` | Omarchy ships an ergonomic tmux config + layout scripts (`tdl`, `tsl`).[^6^] |
| Prompt | `starship` | `starship` ✓ | **HM:** `programs.starship` (`config/starship.toml` → `programs.starship.settings`)[^24^] | |
| System fetch | `fastfetch` | `fastfetch` ✓ | **HM:** `programs.fastfetch`[^24^] | |
| Resource monitor | `btop` | `btop` ✓ | **HM:** `programs.btop` (theme via `programs.btop.themes` or file)[^24^] | |
| Modern CLI set | `eza zoxide fzf fd bat dust ripgrep jq tldr` | `eza` ✓ `zoxide` ✓ `fzf` ✓ `fd` ✓ `bat` ✓ `dust` ✓ `ripgrep` ✓ `jq` ✓ | **HM:** `programs.{eza,zoxide,fzf,fd,bat,ripgrep,jq}` all exist; `tldr` pkg ✓ or `tealdeer` ✓[^24^] | v4 swaps dust → `dua-cli` → nixpkgs attr is **`dua`** (by-name ✓). |
| Editor | `omarchy-nvim` (pre-built LazyVim)[^11^] | `neovim` ✓ (wrapper path verified) | **HM:** `programs.neovim` (dir module); consider **nvf** or nixvim for declarative LazyVim-equivalent | omarchy-nvim is a cached LazyVim snapshot; port via your own nvim config or `LazyVim` starter + `home.file`. |
| Git TUIs | `lazygit`, `lazydocker`, `github-cli` | `lazygit` ✓, `lazydocker` ✓, **`gh`** ✓ (attr name differs!) | **HM:** `programs.lazygit`, `programs.gh` | |
| Version manager | `mise`, `usage` | `mise` ✓, `usage` ✓ (both by-name) | **HM:** `programs.mise` | |
| Script UI lib | `gum` | `gum` ✓ | pkg only | Heavily used by omarchy-* scripts. |
| Menu/writing tools (v4) | `omacut`, `omawrite` | **MISSING (both)** | — | Omarchy 4 in-house tools; package from basecamp sources when released. |
| Clipboard | `wl-clipboard`, (`cliphist` via walker) | `wl-clipboard` ✓, `cliphist` ✓ | **HM:** `services.cliphist`, `services.wl-clip-persist`[^24^] | |

### 2.5 Files, media, screenshots

| Omarchy/Arch component | Arch package | nixpkgs attribute | HM / NixOS module | Notes |
|---|---|---|---|---|
| Screenshot capture | `grim`, `slurp`, `satty` | `grim` ✓, `slurp` ✓, `satty` ✓ | pkg only; alt: `hyprshot` ✓, `grimblast` ✓, `swappy` ✓ | v4 swaps satty → **tensaku (MISSING — custom derivation)**. |
| OCR capture | `tesseract`(+`-data-eng`) | `tesseract` ✓ (attr confirmed via nixpkgs tracker; languages via `tesseract.languages`/override)[^41^] | pkg only | Used by *Capture > Text Extract*.[^1^] |
| File manager | `nautilus`, `nautilus-python`, `sushi` | `nautilus` ✓, `nautilus-python` ✓, `sushi` ✓ | pkg only; **NixOS:** `services.gvfs`, `programs.nautilus-open-any-terminal` if wanted | GTK theming needed (see §5 themes). |
| Image viewer | `imv` | `imv` ✓ | pkg only | |
| Video | `mpv`, `kdenlive`, `gpu-screen-recorder`, `obs-studio` | `mpv` ✓, `kdenlive` ✓ (`kdePackages.kdenlive`, path `pkgs/kde/gear/kdenlive`), `gpu-screen-recorder` ✓, `obs-studio` ✓ (path `pkgs/applications/video/obs-studio`) | **HM:** `programs.mpv`, `programs.obs-studio` | |
| PDF/docs | `evince`, `libreoffice-fresh`, `xournalpp`, `gnome-calculator`, `gnome-disk-utility`, `pinta` | `evince` ✓, `libreoffice` ✓ (attr `libreoffice`/`libreoffice-fresh`, path `pkgs/applications/office/libreoffice`), `xournalpp` ✓, `gnome-calculator` ✓, `gnome-disk-utility` ✓, `pinta` ✓ | pkg only | |
| Screen-share picker CSS | (themed) | — | — | See hyprland-preview-share-picker gap above. |
| Quick calculator in walker | `libqalculate` | `libqalculate` ✓ | pkg only | walker/elephant qalc provider. |

### 2.6 Apps (unfree-heavy tier)

| Omarchy/Arch component | Arch package | nixpkgs attribute | Module | Notes |
|---|---|---|---|---|
| Browser default | `omarchy-chromium` (patched Chromium)[^11^] | `chromium` ✓ (path `pkgs/applications/networking/browsers/chromium`) | **HM:** `programs.chromium` (flags = Omarchy's `chromium-flags.conf`) | Patch delta small → consider `chromium` + flags, or override. |
| Browser alternates | — | `brave` ✓, `firefox` | **HM:** `programs.firefox` ✓; **no `programs.brave`** — use `programs.chromium.package = pkgs.brave` or env packages | |
| Passwords | `1password-beta`, `1password-cli` | `_1password-gui` ✓, `_1password-cli` ✓ (by-name, unfree) | **NixOS:** `programs._1password{,-gui}.enable` (polkit + browser integration) | Unfree → `allowUnfree`. |
| Notes | `obsidian` | `obsidian` ✓ (unfree) | pkg only | |
| Music/comms | `spotify`, `signal-desktop` | `spotify` ✓ (unfree), `signal-desktop` ✓ | pkg only | Both **dropped in v4** (web-app .desktop files instead).[^4^] |
| Markdown editor | `typora` | `typora` ✓ (unfree) | pkg only | Dropped in v4. |
| File sharing | `localsend` | `localsend` ✓ | pkg only | |
| Dev | `docker`, `docker-buildx`, `docker-compose` | `docker` ✓ (path `pkgs/applications/virtualization/docker`), `docker-buildx`, `docker-compose` | **NixOS:** `virtualisation.docker.enable` | `ufw-docker` N/A (see firewall). |
| Web-app launchers | `applications/*.desktop` (HEY, Basecamp, ChatGPT…)[^2^] | — | generate via `writeText`/`xdg.desktopEntries` (HM) | Trivially declarative. |

### 2.7 Look & feel: fonts, icons, GTK/Qt, login, boot

| Omarchy/Arch component | Arch package | nixpkgs attribute | Module | Notes |
|---|---|---|---|---|
| Monospace font | `ttf-jetbrains-mono-nerd` (v4: `-basic`) | **`nerd-fonts.jetbrains-mono`** ✓ (`pkgs/data/fonts/nerd-fonts`)[^26^] | **NixOS:** `fonts.packages` | v4 "basic" = fewer glyphs — use the `nerd-fonts` subset or package the Arch basic variant. |
| Serif/UI writing font | `ttf-ia-writer` | **`ia-writer-mono` ✓, `ia-writer-duospace` ✓, `ia-writer-quattro` ✓** (by-name); `ia-writer-duo` not found | `fonts.packages` | "quattro" coincidence: v4 dev branch is named after the iA Quattro duo-spaced font. |
| Noto family | `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji` | `noto-fonts` ✓, `noto-fonts-cjk-sans` ✓, `noto-fonts-color-emoji` | `fonts.packages` | |
| Icon font | `woff2-font-awesome`, `omarchy.ttf` (custom waybar icons)[^2^] | `font-awesome` ✓ (`pkgs/data/fonts/font-awesome`); **omarchy.ttf = fetch from repo** | `fonts.packages` | |
| Icon theme | `yaru-icon-theme` | **`yaru-theme`** ✓ (attr differs) | pkg / `gtk.iconTheme` (HM `gtk` module) | |
| Qt theming | `kvantum-qt5`, `qt5/6-wayland` | kvantum: **not found as top-level attr** (check `libsForQt5.kvantum`/`qt6Packages` — *unverified*); wayland support is built into qtwayland | **HM:** `qt` module; **NixOS:** `qt.enable` | Flag: confirm kvantum packaging before relying on it. |
| Login manager | `sddm` | — | **NixOS:** `services.displayManager.sddm.enable` (wayland greeter opts) | Omarchy themes sddm (default/sddm). |
| Boot splash | `plymouth` | `plymouth` ✓ | **NixOS:** `boot.plymouth.enable` | Omarchy ships a theme (default/plymouth). |
| Bootloader | `limine` (+snapper-sync hooks) | `limine` ✓ (by-name) | **NixOS:** `boot.loader.limine.*` module exists (verified path)[^24^] | NixOS generations give you rollback natively; snapper optional (`snapper` ✓ + `services.snapper`). |
| Themes | 19 themes in `themes/<name>` + `default/themed/*.tpl` templates + `colors.toml`[^8^][^9^] | — | **This is kebun's core design problem** — see §4.3 | |

### 2.8 Arch-only plumbing with no Nix counterpart

`expac`, `pacman-contrib`, `yay`, `kernel-modules-hook`, `limine-mkinitcpio-hook`, DKMS packages, `linux-firmware-*` splits, `zram-generator` → nixpkgs `zram-generator` ✓ exists but NixOS has `zramSwap` natively; everything else in this class is replaced by NixOS idioms (§4). The `omarchy-keyring` meta package (pacman keyring for the Omarchy repo) has no Nix meaning.[^11^]

**Missing-from-nixpkgs summary (custom derivation or idiom swap required):** `aether` (bjarneo/aether theme-from-image generator — Go, easy to package), `asdcontrol`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `tensaku`, `omacut`, `omawrite` (v4 tools), `tobi-try` (tobi/try — fresh dirs tool), `elephant-1password` (and other elephant providers), `ufw`/`ufw-docker` (idiom swap), `system-config-printer` (idiom swap), `ttf-ia-writer` (use ia-writer-* attrs), `omarchy-walker`/`omarchy-nvim`/`omarchy-chromium`/`omarchy-keyring` (Omarchy meta/patched packages — reimplement intent).[^11^]

---

## 3. Existing community efforts (what to reuse)

1. **henrysipp/omarchy-nix** — https://github.com/henrysipp/omarchy-nix — **729★**, last push 2025-11-13, author states he moved back to Arch Omarchy and is not actively developing it.[^13^] The most direct prior art: a flake exporting `nixosModules.default` + `homeManagerModules.default` with an `omarchy { full_name; email_address; theme; }` option set — i.e., exactly the module shape kebun wants. Reuse: module skeleton, theme option design, and its Hyprland/waybar/walker HM wiring. A community post-mortem of another port ("Yino") cites omarchy-nix's star count as evidence of demand while explaining why a *full* port is a maintenance treadmill.[^18^]
2. **Jylhis/marchyo** — https://github.com/Jylhis/marchyo — 3★, actively pushed (2026-07-26). "Personal spin of Omarchy with NixOS": flake-parts-style modular NixOS+HM config with feature flags (`marchyo.desktop.enable`, etc.) and nixos-hardware integration.[^14^] Reuse: feature-flag module architecture.
3. **richardgill/nix** — https://github.com/richardgill/nix — Omarchy-inspired Nix config; deliberately keeps dotfiles as plain `.conf`/`.json` with mustache templating instead of deep Nix codegen; uses disko + impermanence + sops-nix.[^15^] Reuse: pragmatic "thin Nix layer over plain config files" philosophy — good fit for tracking Omarchy's upstream conf files.
4. **ChrisLAS/hyprvibe** — https://github.com/ChrisLAS/hyprvibe — 143★, active (2026-07-14). Riced Hyprland desktop on NixOS (Jupiter Broadcasting). Reuse: production-grade Hyprland-on-NixOS service wiring.[^16^]
5. **denful/den + garden "anarchy" facet** — https://github.com/vic/den — dendritic, aspect-oriented Nix config framework whose example "anarchy" aspect is explicitly Omarchy-like.[^17^] Reuse: if kebun wants a composable module system rather than a monolith.
6. **Omarchy Discussion #987: "Omarchy + Nix Home Manager Integration"** — https://github.com/basecamp/omarchy/discussions/987 — guide for running HM *on top of* Arch Omarchy, including the key trick of protecting Omarchy-managed dirs (`home.file.".config/omarchy".enable = false` etc.).[^12^] Reuse: hybrid-mode escape hatch and a list of which config trees must stay mutable.
7. **shishi's `omarchy_nix` gist** — https://gist.github.com/shishi/c0a6203145ce7bce873fdf687a11569e — minimal working flake.nix showing omarchy-nix consumption with home-manager as NixOS module.[^12^] Reuse: quick-start template shape.
8. **aorumbayev/awesome-omarchy** — https://github.com/aorumbayev/awesome-omarchy — curated ecosystem list (forks to Fedora/CachyOS/ARM, themes, tooling); watch it for new Nix efforts.[^17^]

Official docs to lean on: NixOS wiki **Hyprland** and **UWSM** pages (UWSM recommended; HM hyprland `systemd.enable = false` caveat; portal setup; display-manager options incl. SDDM/greetd/ly).[^19^][^21^] Hyprland upstream wiki Nix section: https://wiki.hypr.land/Nix/.

---

## 4. Structural mapping: Omarchy (imperative) → kebun (declarative)

### 4.1 `install/*.sh` + `omarchy-*.packages` → NixOS modules
- The two package-list files (`omarchy-base.packages`, `omarchy-other.packages`)[^3^] become `environment.systemPackages` groups inside feature modules (`kebun.desktop.enable`, `kebun.dev.enable`), mirroring Omarchy's `install/packaging/base.sh` phases.
- Hardware branches (`install/hardware/*`: nvidia, T2 Mac, Dell XPS haptics, Surface, ASUS) → per-hardware NixOS modules + `nixos-hardware` imports; kernel params → `boot.kernelParams`; udev rules (e.g. power-profile rules) → `services.udev.extraRules`. Omarchy's "hardware-aware backfill migrations" (e.g. Vulkan driver backfill in v3.8.3)[^1^] are simply expressed as `hardware.graphics.extraPackages` conditionals — no migration needed, evaluation is idempotent.
- Preflight checks (Secure Boot off, disk space) → assertions (`assertions = [{ assertion = …; message = …; }]`).

### 4.2 `config/` + `default/` dotfiles → home-manager
- `config/<app>/*` → HM `xdg.configFile` or native HM `programs.*` settings (§2 tables). Prefer native HM modules where they exist (waybar, hyprlock, mako, swayosd, starship…) and raw files where they don't (walker, elephant, omarchy menu).
- `default/` (the reset-to layer Omarchy copies into `~/.config` on updates) has no Nix analog by design — the store *is* the default layer. Decide per tree: fully managed (store symlink, read-only) vs. seed-once (activation script copies only if absent) vs. user-owned. Omarchy's own docs treat `~/.config/hypr`, `~/.config/omarchy` as user-editable;[^12^] kebun should keep at least `hypr/` overridable (e.g. generate `hyprland.conf` but `source` an optional `~/.config/hypr/custom.conf` at the end — exactly how Omarchy splits `bindings.conf`/`looknfeel.conf`).
- `applications/*.desktop` web-app launchers → HM `xdg.desktopEntries`.

### 4.3 `themes/` + `default/themed/*.tpl` → a Nix theme module (the heart of kebun)
Omarchy v3.8 themes: `themes/<name>/{colors.toml, backgrounds/, btop.theme, neovim.lua, vscode.json, icons.theme, keyboard.rgb}`; `omarchy-theme-set` renders `default/themed/*.tpl` templates with the palette into `~/.config/omarchy/current/theme/`, then swaps `current/` atomically and reloads apps.[^8^][^9^][^10^]

Two porting strategies (can coexist):

- **A. Declarative (recommended default):** parse each theme's `colors.toml` at eval time (`builtins.fromTOML`) into an attrset; one Nix function `mkTheme :: attrs -> { hyprlandConf; waybarCss; makoIni; alacrittyToml; … }` renders the 18 template outputs per app (same mapping as `default/themed/`)[^9^]; active theme selected by a `kebun.theme = "tokyo-night"` option; switching = `nixos-rebuild switch` (or `home-manager switch` for instant user-level swap). App configs include the generated palette file, mirroring Omarchy's `~/.config/omarchy/current/theme/*` includes.
- **B. Runtime switching (Omarchy-faithful):** build *all* themes into the store (`pkgs.linkFarm` per theme), keep a **mutable symlink** `~/.config/omarchy/current` managed outside the store (HM activation script points it at the chosen store path), and a `kebun-theme-set` script (`writeShellScriptBin`) that flips the symlink and runs the same reload commands Omarchy uses (`hyprctl reload`, `systemctl --user restart waybar`, `makoctl reload`, kill/restart swayosd…). This preserves Omarchy's instant, no-rebuild theme UX at the cost of one impure inode. Impure escape hatch if you also want live-editing: `config.lib.file.mkOutOfStoreSymlink` to a dotfiles checkout.

### 4.4 `bin/omarchy-*` (283 scripts) → packaged script library + module glue
- Port the script corpus as `pkgs.writeShellScriptBin`/`writeShellApplication` entries in a `kebun-scripts` package (keeps Omarchy's `omarchy-<noun>-<verb>` namespace and `omarchy:summary=` metadata header convention).[^29^]
- Scripts fall into classes; don't port blindly:
  - **Pure UX helpers** (brightness, audio switch, screenshots, theme set, font set, menu launchers) → port 1:1.
  - **System mutators** (`omarchy-channel-set`, `omarchy-branch-set`, update/reinstall scripts, `*-migration*`) → **replace** with flake inputs + `nixos-rebuild`; do not port. This is where the distros genuinely diverge.
  - **Installers** (`omarchy-install-*` for optional apps like RetroArch, Docker, 1Password)[^1^] → kebun module options (`kebun.gaming.retroarch.enable = true`) — an "install" is a rebuild, which is *more* Omakase than a menu that runs pacman.
- The `omarchy` unified CLI (v3.7+)[^1^] → a thin `writeShellScriptBin "omarchy"` dispatcher over the ported scripts (or rename to `kebun`).

### 4.5 `migrations/` → NixOS idioms
- Omarchy migrations are timestamped bash scripts run once per install on update. In kebun: config changes are atomic generations (rollback via bootloader entries — same UX as Omarchy's limine+snapper snapshots).[^1^]
- For stateful fixups that must touch `$HOME` (e.g. rewriting a user-modified tmux conf as v3.8.3 did), use HM `home.activation` scripts with a guard marker (write `~/.local/state/kebun/migrations/<id>.done`), or `system.activationScripts` for `/etc`-level state. `system.stateVersion` + `home.stateVersion` pin baseline semantics.

---

## 5. Gotchas: Arch-isms that don't map cleanly

1. **AUR / `yay` is the biggest conceptual gap.** Omarchy's install menus and several defaults assume AUR (`yay` is in the base package list).[^3^] kebun needs: (a) everything in nixpkgs (true for ~90% of the stack, §2), (b) custom derivations for the Omarchy-specific and small tools listed in §2.8 — all are tiny (Go/Rust/C single binaries or font tarballs), (c) **no user-facing "install anything" escape hatch** comparable to AUR; the kebun answer is "add it to the module" or `nix profile` for ad-hoc.
2. **Omarchy's own packages are unpackaged source of truth.** `omarchy-chromium` (patched browser), `omarchy-nvim` (cached LazyVim snapshot), `omarchy-walker` (meta + elephant provider bundle), `omarchy-keyring` come from omacom-io repos, not AUR.[^11^] Each is a small flake input + derivation; `omarchy-chromium` is likely best replaced by vanilla `chromium` + `programs.chromium.commandLineArgs` from `chromium-flags.conf` unless the patches matter to you.
3. **`/etc` and FHS paths.** Omarchy writes `/etc/vconsole.conf` (into initramfs), `/etc/pacman.d/hooks`, `/etc/limine`, plymouth/sddm theme dirs, `environment.d` user env.[^1^][^2^] NixOS equivalents: `console.keyMap`/`boot.initrd`, no hook system needed (module `config` *is* the hook), `boot.loader.limine`, `boot.plymouth.theme*`, `services.displayManager.sddm.theme`, `home.sessionVariables`/`systemd.user.sessionVariables`. Anything grepping `/etc/os-release` for `ID=arch` (Omarchy scripts do this) breaks — patch the ported scripts.
4. **systemd user services under UWSM.** Omarchy relies on uwsm's unit wrapping (`uwsm app`, `wayland-session@Hyprland.target`). On NixOS: `programs.hyprland.withUWSM = true` + `programs.uwsm`; HM services (waybar, mako, hypridle, cliphist, elephant…) integrate via `systemd.user.services` with `partOf`/`after = [ "graphical-session.target" ]` — HM modules already do this, **but** set `wayland.windowManager.hyprland.systemd.enable = false` or it fights UWSM.[^19^][^21^] There are known papercuts with uwsm session discovery when no display manager is enabled (nixpkgs#485123) — kebun should ship a display-manager (SDDM, matching Omarchy) or document `services.displayManager.sessionPackages`.[^21^]
5. **Theme switching writes files.** Omarchy's `omarchy-theme-set` mutates `~/.config/omarchy/current/` and app symlinks (incl. a *Neovim theme symlink* that broke across the v4 theme-path move in v3.8.4).[^1^][^10^] Fully-managed HM files are read-only store symlinks — any app that *writes* its config (Obsidian, VS Code settings sync, walker CSS overrides discussed in omarchy#1182)[^30^] will fight it. Choose per-app: managed (regenerate on switch), or seed-once + app-writable. GTK/theming state (`gsettings`, dconf) needs HM `dconf.settings`/`gtk.*`, not file writes.
6. **Unfree defaults.** 1Password, Spotify, Typora, Obsidian, Chrome-ish flags — kebun must set `nixpkgs.config.allowUnfree = true` (or predicate) or drop them (v4 already drops Spotify/Signal/Typora for web apps — a cleaner default for a Nix port).[^4^]
7. **Rolling vs pinned cadence.** Omarchy is Arch-rolling with weekly-monthly releases and *expects* fresh Hyprland (0.55 already, Lua config migration coming).[^1^][^19^] Pin kebun to `nixos-unstable` (or the current stable + selected unstable overlays for hypr*/walker/quickshell) and expect to bump flake inputs on Omarchy's minor-release rhythm; omarchy-nix's stall shows what happens if you don't.[^13^]
8. **Snapshots/rollback duplication.** Omarchy invests in limine+snapper+btrfs snapshots; NixOS generations already give boot-menu rollback. Keep btrfs snapshots only for `$HOME` data; don't port `limine-snapper-sync` machinery.
9. **Hardware DKMS packages** (broadcom-wl, T2 Mac, yt6801, tuxedo-drivers) → `boot.kernelPackages`/`boot.extraModulePackages` and nixos-hardware modules; some (e.g. `dell-xps-touchpad-haptics`, `intel-ipu7-camera`) may be missing from nixpkgs — verify per target machine.
10. **`omarchy.ttf` icon font and other in-repo assets** — fetch straight from `basecamp/omarchy` (`fetchurl`/flake input with rev pinning) into `fonts.packages`; don't hand-copy.

---

## Footnotes

[^1^]: Omarchy releases (tags, dates, release notes incl. v3.8.4 2026-07-21, v3.8.2 "Hyprland 0.55 compatibility", v3.7.0 unified `omarchy` CLI, v3.8.3 tmux/CSI-u + Vulkan backfill): https://github.com/basecamp/omarchy/releases (data cross-checked via GitHub API 2026-07-27)
[^2^]: Omarchy repo metadata (24,120 stars, default branch `quattro`, tree layout: `config/`, `default/`, `themes/`, `bin/` [283 scripts], `applications/`, `install/`): https://github.com/basecamp/omarchy ; v4 alpha mentioned in https://github.com/basecamp/omarchy/issues/5948
[^3^]: v3.8.x package lists: https://github.com/basecamp/omarchy/blob/master/install/omarchy-base.packages and https://github.com/basecamp/omarchy/blob/master/install/omarchy-other.packages
[^4^]: Omarchy 4 (`quattro`) package list (quickshell-git, foot, networkmanager, tensaku, omacut/omawrite added; waybar/walker/mako/hypridle/hyprlock/swayosd/alacritty/iwd/satty/playerctl/spotify/signal-desktop/typora removed): https://github.com/basecamp/omarchy/blob/quattro/install/omarchy-base.packages and branch tree https://github.com/basecamp/omarchy/tree/quattro
[^6^]: Omarchy Manual — Terminal ("Alacritty is the default… we fully support Ghostty, Foot, and Kitty… Pick your preference under Install > Terminal"; tmux `tdl`/`tsl`): https://learn.omacom.io/2/the-omarchy-manual/106/terminal
[^7^]: `xdg-terminals.list` on master (Alacritty.desktop first; comment "first found and valid terminal will be used"): https://github.com/basecamp/omarchy/blob/master/config/xdg-terminals.list
[^8^]: Themes directory (19 themes; per-theme files: colors.toml, backgrounds/, btop.theme, neovim.lua, vscode.json, icons.theme, keyboard.rgb): https://github.com/basecamp/omarchy/tree/master/themes
[^9^]: Theme templates (`alacritty.toml.tpl … waybar.css.tpl, walker.css.tpl, mako.ini.tpl, hyprland.conf.tpl, hyprlock.conf.tpl, ghostty.conf.tpl, kitty.conf.tpl, foot.ini.tpl, swayosd.css.tpl, btop.theme.tpl…`): https://github.com/basecamp/omarchy/tree/master/default/themed
[^10^]: `omarchy-theme-set` (copy official theme → overlay user theme → render templates → atomic swap of `~/.config/omarchy/current/theme`): https://github.com/basecamp/omarchy/blob/master/bin/omarchy-theme-set
[^11^]: Omarchy-specific/non-mirror packages (asdcontrol, hyprland-preview-share-picker, omarchy-chromium, omarchy-keyring, omarchy-nvim, omarchy-walker, tobi-try, wayfreeze; upstream URLs): https://github.com/basecamp/omarchy/discussions/3923
[^12^]: Omarchy + Nix Home Manager integration (protecting Omarchy-managed dirs): https://github.com/basecamp/omarchy/discussions/987 ; gist consumption example: https://gist.github.com/shishi/c0a6203145ce7bce873fdf687a11569e
[^13^]: henrysipp/omarchy-nix (729★, module shape, maintenance status note): https://github.com/henrysipp/omarchy-nix
[^14^]: Jylhis/marchyo: https://github.com/Jylhis/marchyo
[^15^]: richardgill/nix: https://github.com/richardgill/nix
[^16^]: ChrisLAS/hyprvibe (143★): https://github.com/ChrisLAS/hyprvibe
[^17^]: denful/den (dendritic "anarchy" facet): https://github.com/vic/denful ; awesome-omarchy ecosystem list: https://github.com/aorumbayev/awesome-omarchy
[^18^]: Yino post-mortem (why a full Omarchy NixOS port is a treadmill; cites omarchy-nix): https://git.smith.eu/m/yino/commit/6c6a82937fe942db80df6d4fd95eeb0d8cff9f7e
[^19^]: NixOS Wiki — Hyprland (programs.hyprland.withUWSM; HM `wayland.windowManager.hyprland.systemd.enable = false` under UWSM; portals; display managers; v0.55 Lua config notice + HM Lua support since 26.05): https://wiki.nixos.org/wiki/Hyprland
[^20^]: nixpkgs by-name verification: walker 2.17.0 https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/wa/walker/package.nix ; elephant 2.22.0 https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/el/elephant/package.nix
[^21^]: NixOS Wiki — UWSM (`programs.uwsm`, `programs.hyprland.withUWSM`, HM caveat): https://wiki.nixos.org/wiki/UWSM ; uwsm session-discovery papercut: https://github.com/NixOS/nixpkgs/issues/485123
[^22^]: quickshell in nixpkgs: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/qu/quickshell/package.nix
[^23^]: NixOS Hyprland module: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/programs/wayland/hyprland.nix ; UWSM module: …/nixos/modules/programs/wayland/uwsm.nix ; hyprlock: …/nixos/modules/programs/wayland/hyprlock.nix ; limine: …/nixos/modules/system/boot/loader/limine/limine.nix
[^24^]: home-manager modules verified at https://github.com/nix-community/home-manager/tree/master/modules — `services/window-managers/hyprland.nix`, `programs/{waybar,hyprlock,fuzzel,rofi,wofi,tofi,ghostty,alacritty,kitty,foot,starship,fastfetch,btop,eza,zoxide,fzf,fd,bat,ripgrep,lazygit,mise,neovim,chromium,firefox,quickshell,wlogout}.nix`, `services/{hypridle,hyprpaper,hyprsunset,hyprpolkitagent,mako,dunst,swayosd,cliphist,udiskie,blueman-applet,network-manager-applet,wl-clip-persist,elephant,swaync}.nix`
[^25^]: Absence of `programs/walker` in HM (no `walker.nix` under modules/programs; elephant service exists): https://github.com/nix-community/home-manager/tree/master/modules/programs and …/modules/services/elephant.nix
[^26^]: nixpkgs path verifications: polkit_gnome https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/po/polkit_gnome/package.nix ; xdg-desktop-portal-hyprland https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/applications/window-managers/hyprwm/xdg-desktop-portal-hyprland ; nerd-fonts https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/data/fonts/nerd-fonts/default.nix ; ia-writer-quattro https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ia/ia-writer-quattro/package.nix ; yaru-theme https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ya/yaru-theme/package.nix ; kdenlive https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/kde/gear/kdenlive/default.nix
[^27^]: Terminal-launch changes across Omarchy versions (gazelle-tui integration notes, Nov 2025 & v3.2.0 rework): https://github.com/Zeus-Deus/gazelle-tui
[^28^]: Ghostty-default period report (Dec 2025; xdg-terminals.list mechanics): https://travis.media/blog/set-default-terminal-omarchy-linux/
[^29^]: omarchy bin script corpus & metadata header convention (`# omarchy:summary=`): https://github.com/basecamp/omarchy/tree/master/bin
[^30^]: Walker CSS customization discussion (app-writable config tension): https://github.com/basecamp/omarchy/discussions/1182
[^40^]: Elephant 1Password provider packaging (`elephant-1password` via yay): https://github.com/basecamp/omarchy/discussions/3679
[^41^]: `tesseract` attr & `.languages` in nixpkgs: https://github.com/NixOS/nixpkgs/issues/440907

*Uncertainty flags: Omarchy 4 internals (lock/idle/notification handling inside Quickshell) are inferred from package-list diffs, not documented upstream yet; `kvantum` top-level attr unverified; `omawrite` nixpkgs check hit a network timeout (treated as missing); `ia-writer-duo` not found though mono/duospace/quattro exist.*
