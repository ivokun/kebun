# Omarchy Repository — Structural Research Brief

**Repository:** https://github.com/basecamp/omarchy — *"Beautiful, Modern & Opinionated Linux"* (DHH / Basecamp org)
**Snapshot date:** 2026-07-27 · **Tree SHA:** `ada53b090ed705a4353c9db19b970bddd0eb6aa3` · 1,552 tree entries, non-truncated [^2^]
**Default branch:** `quattro` (this is what `HEAD` resolves to; all `raw…/HEAD/…` URLs below fetch this branch) [^1^]
**Version on HEAD (`version` file):** `4.0.0.alpha` — Omarchy "Quattro", the in-development v4 [^5^]
**Latest stable tag/release:** `v3.8.4` (published 2026-07-21); recent tags: v3.8.4 → v3.8.3 (2026-07-13) → v3.8.2 → v3.8.1 → v3.8.0 (2026-05-09) [^3^][^4^]
**Stars:** ~24.1k; last push 2026-07-26 [^1^]

> ⚠️ **Key finding for the kebun port:** the default branch is mid-transition to **Omarchy 4 "Quattro"**. The classic stack (waybar, walker, mako, swayosd, hypridle, hyprlock, rofi, `hyprland.conf`) is **gone** on HEAD. Quattro replaces them with:
> - **Hyprland configured entirely in Lua** (`config/hypr/*.lua` + `default/hypr/*.lua`) using Hyprland's new `hl.*` Lua API. [^10^][^18^]
> - **A single long-running Quickshell instance (`omarchy-shell`)** hosting the bar, launcher/menu, notifications, OSD, lock screen, clipboard manager, emoji picker, and settings panels as QML plugins (`shell/`). [^8^][^50^]
> - **Themes reduced to one `colors.toml` palette file** per theme + generated templates (`default/themed/*.tpl`) rendered into `~/.local/state/omarchy/current/theme/`. [^36^][^49^]
> - A theme-able **Plymouth boot theme, SDDM QML theme, Limine bootloader + Snapper snapshot** story.
> A migration helper `bin/omarchy-upgrade-to-quattro` exists for v3 → v4 upgrades. [^2^]
>
> Recent commits on `quattro` (2026-07-26): webcam-overlay anchoring, zram sized "the way Fedora does", return to stock libfprint, pending-migration checks only at login. [^52^]

---

## 1. README highlights

The README is minimal (9 lines): *"Omarchy is a beautiful, modern & opinionated Linux distribution by DHH. Read more at omarchy.org."* — MIT licensed. [^6^] All substance lives in `docs/`, `AGENTS.md`, and the tree itself. Contributor/style rules (bash style, `omarchy-*` command naming, `# omarchy:summary=` CLI metadata convention) live in `AGENTS.md`. [^9^]

## 2. Top-level directory anatomy

From the live tree (blob counts in parentheses) [^2^]:

| Path | Purpose |
|---|---|
| `README.md`, `LICENSE`, `AGENTS.md`, `icon.*`, `logo.*` | Meta/branding; logo/icon also shipped to `/usr/share/omarchy` and `/etc/skel/.config/omarchy/branding/` [^7^] |
| `version` | Single line: `4.0.0.alpha`; installed to `/usr/share/omarchy/version` [^5^][^7^] |
| `bin/` (380) | Every `omarchy-*` user-facing command + the `omarchy` router CLI (see §8) [^37^] |
| `config/` (72) | User dotfiles seeded into `/etc/skel/.config/**` (→ `~/.config/**`); also kept at `/usr/share/omarchy/config/**` as resync source (see §5) [^7^] |
| `default/` (213) | Package-owned defaults: Hyprland Lua defaults, bash env, theme templates (`default/themed/`), Plymouth/SDDM/Limine/snapper configs, systemd units, pacman channel configs, uwsm env, Chromium extensions [^7^] |
| `etc/` (56) | `/etc` drop-ins owned outright: NetworkManager, systemd, sudoers, sysctl, mkinitcpio, SDDM, faillock, fastfetch (`/etc/fastfetch/config.jsonc`) [^7^] |
| `install/` (91) | Root-side install/finalize scripts + the two package lists (see §4) [^33^] |
| `migrations/` (41) | Timestamped per-user idempotent fix-up scripts run by `omarchy-migrate` (see §10) [^38^] |
| `themes/` (294) | 22 bundled themes (see §7) [^36^] |
| `shell/` (207) | The Quickshell desktop: QML UI kit, plugin system, bar/panels/services (see §9) [^8^] |
| `applications/` (37) | `.desktop` launchers for webapps (HEY, ChatGPT, Discord, WhatsApp, X, YouTube, Zoom, Google Maps/Photos/Messages/Contacts…) + icons [^2^] |
| `docs/` (7) | `file-layout.md`, `omarchy-shell.md`, `theming.md`, `migrations.md`, `update-process.md`, `AUDIO-TUNING.md` [^7^][^8^] |
| `test/` (138) | Bats-style test suite for bin scripts, install, shell, theming [^2^] |
| `.github/`, `.luarc.json`, `.editorconfig` | CI/issue templates; Lua LSP config (the config is Lua now) [^2^] |

**Packaging model** (from `docs/file-layout.md`): the repo builds into two Arch packages whose PKGBUILDs live in the separate `omarchy-pkgs` repo — **`omarchy`** (bin, install, migrations, themes, shell) and **`omarchy-settings`** (`/etc/skel` seed, `/etc` drop-ins, fonts, Plymouth/SDDM themes, limine/snapper configs). Two more stand-alone packages: `omarchy-keyring`, `omarchy-nvim`. `$HOME` is populated in three layers: **Seed** (`/etc/skel` via `useradd -m`), **Finalize** (`omarchy-finalize-user`, once per user), **Resync** (`omarchy-reinstall-configs`, destructive reset). [^7^]

## 3. Install flow (`install/`)

Root-side orchestration is `omarchy-setup-system` (run in chroot by the ISO at finalization), logging to `/var/log/omarchy-install.log` via `install/helpers/logging.sh`. It sources four `all.sh` phase runners [^7^][^33^]:

1. **`install/config/all.sh`** → `theme-system.sh`, `increase-lockout-limit.sh`, `lockscreen-pam.sh`, `fix-powerprofilesctl-shebang.sh`, `docker.sh`, `snapper.sh`, `enable-services.sh`, `firewall.sh` [^33^]
2. **`install/hardware/all.sh`** (via `omarchy-setup-hardware`) → ASUS ROG/PTL fixes, Framework 16 (QMK HID), Dell XPS touchpad haptics, Surface, network/Bluetooth/regdom, NVIDIA, Vulkan; Intel subtree (`ptl-kernel.sh` — Panther Lake kernel swap, `ipu7-camera.sh`, `fred.sh`, Wi-Fi 7 EHT fix, sof-firmware, thermald, video-acceleration); Apple T2 fixes (spi keyboard, suspend-nvme, t2); Lenovo Yoga bass speakers [^34^]
3. **`install/login/all.sh`** → `sddm.sh` (SDDM theme/session) [^35^]
4. **`install/post-install/all.sh`** → `pacman.sh`, `udev.sh`, `localdb.sh` [^35^]

Per-user finalize: `install/user/all.sh` → `theme.sh`, `git.sh`, `xcompose.sh`, `mise-work.sh`, per-vendor audio/mic fixes, `default-keyring.sh`, `mise.sh`; plus `install/user/first-run/*.sh` on first graphical login (welcome, Wi-Fi toast, GNOME/GTK dconf settings, user unit enablement, voxtype hook). [^35^][^7^]

**ISO / boot mechanism (high level):** No ISO builder or archinstall profile exists in this repo (grep for `iso`/`archinstall` paths in the tree returns nothing). The ISO is built externally (the `omarchy-pkgs` repo; the comments in the package lists state *"The ISO builder also reads this file when constructing the offline mirror"*). The ISO pacstraps `install/omarchy-base.packages`, then runs `omarchy-setup-system` (root) and `omarchy-finalize-user --force --first-install` (user) in the target chroot. Boot chain on the installed system: **Limine** bootloader (`default/limine/limine.conf`, `etc/limine-entry-tool.d/omarchy-{defaults,uki}.conf`, UKI entries) → **Plymouth** (`default/plymouth/` Omarchy theme) → LUKS/snapper rollback via `limine-snapper-sync` → **SDDM** (QML theme `default/sddm/omarchy/`) → **uwsm**-managed Hyprland session (`default/wayland-sessions/omarchy.desktop`). [^31^][^32^][^7^]

## 4. Package / dependency lists

Declared in two flat files read by the ISO builder (PKGBUILDs live in `omarchy-pkgs`, not here):

**`install/omarchy-base.packages`** (142 packages, pacstrapped by the ISO) — core stack [^31^]:
- **WM/desktop:** `hyprland`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `hyprpicker`, `hyprsunset`, `quickshell-git`, `uwsm`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-hyprland`, `xdg-terminal-exec`, `qt5-wayland`, `sddm`, `plymouth`
- **Terminals:** `foot` (plus config for alacritty/ghostty/kitty — installable via `omarchy-install-terminal`)
- **Shell/CLI:** `starship`, `tmux`, `fzf`, `zoxide`, `eza`, `bat`, `fd`, `ripgrep`, `mise`, `usage`, `gum`, `jq`, `tldr`, `fastfetch`, `btop`, `dua-cli`, `lazygit`, `lazydocker`, `yay`
- **Audio:** `wireplumber`, `pamixer`, `asdcontrol`
- **Apps:** `chromium`, `nautilus`, `imv`, `mpv`, `obsidian`, `omawrite`, `omacut`, `tensaku` (screenshot annotator replacing Satty), `cliamp`, `evince`, `libreoffice-fresh`, `gnome-calculator`, `gnome-disk-utility`, `kdenlive`, `obs-studio`, `pinta`, `xournalpp`, `localsend`, `moonlight-qt`, `sushi`
- **Editors/AI:** `nvim`, `omarchy-nvim`, plus `aether`, `tobi-try` (Basecamp-internal tools)
- **System:** `networkmanager`, `bluez*`, `cups*`, `docker*`, `ufw`, `power-profiles-daemon`, `fcitx5*` (IME), `gnome-keyring`, `libsecret`, `wl-clipboard`, `wtype`, `grim`, `slurp`, `gpu-screen-recorder`, `tesseract` (OCR), `yt-dlp`, `ffmpegthumbnailer`, `imagemagick`, `udiskie`, `plocate`, `inotify-tools`, `noto-fonts*`, `ttf-jetbrains-mono-nerd-basic`, `ttf-ia-writer`, `woff2-font-awesome`, `yaru-icon-theme`, `kvantum-qt5`, `gnome-themes-extra`, `lua51`, `luarocks`, dev tools (`clang`, `llvm`, `rust`, `ruby`, `dotnet-runtime`, `python-*`), `mariadb-libs`, `postgresql-libs`, `qemu-user-static-binfmt`, `tensaku`, `voxtype` deps via hook [^31^]

**`install/omarchy-other.packages`** (~70 packages outside the base pacstrap; hardware/optional) [^32^]: kernel stack (`linux`, `linux-ptl`, `linux-t2`, firmware, headers), **boot/snapshot:** `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `snapper`, `btrfs-progs`, `zram-generator`; **NVIDIA:** `nvidia{,-open,-580xx}-dkms`, `nvidia-utils`, `lib32-*`, `egl-wayland`, `libva-nvidia-driver`; **PipeWire:** `pipewire{,-alsa,-jack,-pulse}`, `gst-plugin-pipewire`, `libpulse`; **hardware:** `broadcom-wl`, `macbook12-spi-driver-dkms`, `apple-bcm-firmware`, `apple-t2-audio-config`, `t2fanrd`, `tiny-dfr`, `tuxedo-drivers-nocompatcheck-dkms`, `yt6801-dkms`, `dell-xps-touchpad-haptics`, `intel-ipu7-camera`, `intel-lpmd`, `intel-media-driver`, `sof-firmware`, `thermald`, `asusctl`, `qmk-hid`, Vulkan drivers (`vulkan-intel/radeon/asahi`), `lsp-plugins-lv2` (speaker tuning), `linux-firmware-marvell`. [^32^]

## 5. `config/` — every configured application

`config/**` → `/etc/skel/.config/**` (seeded at user creation; resync via `omarchy-reinstall-configs`). [^7^]

| App | File(s) | Controls |
|---|---|---|
| **Hyprland** | `config/hypr/{hyprland,bindings,input,looknfeel,monitors,autostart}.lua`, `hyprsunset.conf`, `xdph.conf` | Full WM config in Lua — see §6. `hyprsunset.conf`: identity profile at 07:00 (night-light off by default, example 4000K@20:00 commented). `xdph.conf`: screencopy portal, `custom_picker_binary = hyprland-preview-share-picker` [^16^][^17^] |
| **Alacritty** | `config/alacritty/alacritty.toml` | Imports generated theme `~/.local/state/omarchy/current/theme/alacritty.toml`; JetBrainsMono Nerd Font 9; padding 14; `decorations="None"`; OSC52 copy/paste; Shift+Insert paste [^39^] |
| **Ghostty** | `config/ghostty/config` | Optional theme include `…/current/theme/ghostty.conf`; JetBrainsMono 9; padding 14; block cursor; shell-integration for SSH terminfo [^40^] |
| **Kitty** | `config/kitty/kitty.conf` | Theme include; JetBrainsMono 9; hidden decorations; Ctrl/Shift+Insert clip; CSI-u Shift+Enter / Alt+Shift+Enter for tmux; remote control on [^41^] |
| **Foot** | `config/foot/foot.ini` | Theme include; JetBrainsMono 9, pad 14x14, block cursor, 10k scrollback, Ctrl+Insert/Ctrl+Shift+c copy etc. [^42^] |
| **Starship** | `config/starship.toml` | Minimal format `[$directory$git_branch$git_status]($style)$character`, cyan ❯, truncation 2 [^43^] |
| **tmux** | `config/tmux/tmux.conf` | Prefix `C-Space` (+`C-b`); vi copy mode; Alt+Enter vsplit / Alt+Shift+Enter hsplit; popup keybinding help via `omarchy-menu-tmux-keybindings` [^44^] |
| **btop** | `config/btop/btop.conf` | `color_theme = "current"` (generated from Omarchy theme), truecolor [^45^] |
| **lazygit** | `config/lazygit/config.yml` | (small YAML config; theming via generated values) [^2^] |
| **Chromium** | `config/chromium-flags.conf`, `config/chromium/Default/Preferences` | Wayland ozone flags, gnome-libsecret password store, force-loads two bundled extensions (`copy-url`, `yt-dlp`) from `/usr/share/omarchy/default/chromium/extensions` [^46^] |
| **git** | `config/git/config` | Aliases, `pull.rebase`, histogram diff, `push.autoSetupRemote`, commit verbose [^47^] |
| **fcitx5** | `config/fcitx5/conf/{clipboard,xcb}.conf` | IME: clipboard watch, XCB front-end [^2^] |
| **imv** | `config/imv/config` | Image viewer defaults [^2^] |
| **hyprland-preview-share-picker** | `…/config.yaml` | Screen-share picker UI config [^2^] |
| **Obsidian** | `config/obsidian/user-flags.conf` | Electron flags [^2^] |
| **opencode** | `config/opencode/opencode.json` | AI agent config [^2^] |
| **wireplumber** | `…/bluetooth-a2dp-autoconnect.conf` | BT A2DP auto-connect [^2^] |
| **xournalpp** | `config/xournalpp/settings.xml` | Drawing app defaults [^2^] |
| **omarchy (self)** | `config/omarchy/shell.json`, `extensions/omarchy-menu.jsonc`, `hooks/*.d/*.sample`, `themed/alacritty.toml.tpl.sample` | Shell layout config (bar position/layout, idle timers: screensaver 150s / lock 300s) [^48^]; user hook system (`theme-set.d`, `font-set.d`, `post-boot.d`, `post-update.d`, `battery-low.d`, `pre-refresh-pacman.d`) [^2^] |
| **autostart** | `config/autostart/*.desktop` | `limine-snapper-notify`, `org.fcitx.Fcitx5`, `print-applet` XDG autostart entries [^2^] |

> **Gone vs. Omarchy v3:** no `waybar/`, `walker/`, `rofi/`, `mako|dunst/`, `swayosd/`, `hypridle/`, `hyprlock/`, `hyprpaper/` directories exist on HEAD — those roles are now Quickshell plugins (`shell/plugins/{bar,menu,notifications,osd,lock,background,clipboard,emojis}`). [^2^][^8^]

## 6. Hyprland configuration (Lua) — deep dive

### 6.1 Load chain

User entry point `~/.config/hypr/hyprland.lua` bootstraps `$OMARCHY_PATH` (default `/usr/share/omarchy`) and then [^10^]:

```lua
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")
require("default.hypr.omarchy")   -- all Omarchy defaults
require("hypr.monitors")          -- user overrides, loaded after defaults
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("default.hypr.toggles")   -- dynamic toggle flags
```

`default/hypr/omarchy.lua` loads helpers → autostart → bindings (media, clipboard, tiling, utilities, voxtype, applications) → envs → looknfeel → input → windows → **current theme overrides** (`omarchy.current.theme.hyprland`). Kill-switches: `omarchy_default_bindings = false` and `omarchy_preinstalled_bindings = false`. [^18^]

The user-side files (`config/hypr/monitors.lua`, `input.lua`, `looknfeel.lua`, `bindings.lua`, `autostart.lua`) ship as **commented example overrides** — the real defaults live in `default/hypr/`. User `monitors.lua` sets `GDK_SCALE=2`, `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })`. [^14^][^11^][^12^][^13^][^15^]

### 6.2 Look & feel — VERBATIM `default/hypr/looknfeel.lua` [^19^]

```lua
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/

local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactive_border_color = "rgba(595959aa)"

hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 2,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },

    resize_on_border = false,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,

    shadow = {
      enabled = false,
    },

    blur = {
      enabled = false,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },

    groupbar = {
      font_size = 12,
      font_family = "monospace",
      font_weight_active = "ultraheavy",
      font_weight_inactive = "normal",
      indicator_height = 0,
      indicator_gap = 5,
      height = 22,
      gaps_in = 5,
      gaps_out = 0,
      text_color = "rgb(ffffff)",
      text_color_inactive = "rgba(ffffff90)",
      col = {
        active = "rgba(00000040)",
        inactive = "rgba(00000020)",
      },
      gradients = true,
      gradient_rounding = 0,
      gradient_round_only_edges = false,
    },
  },

  animations = {
    enabled = true,
  },
})

-- Default animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 3.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "fadeSwitch", enabled = false })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = false })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slidevert" })

hl.config({
  dwindle = {
    preserve_split = true,
    force_split = 2,
  },

  scrolling = {
    column_width = 0.49,
  },

  master = {
    new_status = "master",
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    disable_scale_notification = true,
    focus_on_activate = true,
    anr_missed_pings = 3,
    on_focus_under_fullscreen = 1,
    initial_workspace_tracking = 0,
  },

  cursor = {
    hide_on_key_press = true,
    warp_on_change_workspace = 1,
  },

  binds = {
    hide_special_on_workspace_change = true,
  },
})
```

**Highlights:** gaps 5/10, border 2px gradient `rgba(33ccffee)→rgba(00ff99ee)` @45° (theme-overridable), **rounding 0, blur off, shadows off**, dwindle layout (with `scrolling` layout preconfigured at `column_width = 0.49` for the niri-like toggle), animations on with custom bezier curves, workspace animations disabled. [^19^]

### 6.3 Input — VERBATIM `default/hypr/input.lua` (config portion) [^20^]

```lua
hl.config({
  input = {
    kb_layout = vconsole.XKBLAYOUT or "us",
    kb_variant = vconsole.XKBVARIANT or "",
    kb_model = "",
    kb_options = "compose:caps,shift:both_capslock",
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,

    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Scroll nicely in the terminal.
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
```

(Keyboard layout is read from `/etc/vconsole.conf` at runtime.) [^20^]

### 6.4 Window rules & env

- `default/hypr/windows.lua`: global `suppress_event = "maximize"`; all windows tagged `+default-opacity` then `opacity = "0.985 0.96"`; XWayland drag-fix rule; per-app rules loaded from `default/hypr/apps/*.lua` (19 modules: 1password, battlenet, bitwarden, browser, davinci-resolve, geforce, jetbrains, localsend, moonlight, omarchy-shell, pip, qemu, retroarch, screenshot-selection, steam, system, telegram, terminals, webcam-overlay). Terminals are tagged `+terminal` with matching opacity. [^22^][^51^][^30^]
- `default/hypr/envs.lua`: forces Wayland everywhere (`GDK_BACKEND`, `QT_QPA_PLATFORM`, `QT_STYLE_OVERRIDE=kvantum`, `MOZ_ENABLE_WAYLAND`, `ELECTRON_OZONE_PLATFORM_HINT`, …), `XCURSOR_SIZE=24`, `XCOMPOSEFILE=~/.XCompose`, `xwayland.force_zero_scaling = true`, `ecosystem.no_update_news = true`, prepends `$OMARCHY_PATH/bin` to PATH, loads NVIDIA env module + theme gum env. [^21^]
- `default/hypr/autostart.lua` (on `hyprland.start`): imports environment into systemd user manager, then launches **`quickshell -n -p $OMARCHY_PATH/shell`** (the desktop shell), `fcitx5`, `omarchy-first-run`, `omarchy-powerprofiles-init`, `omarchy-hyprland-monitor-watch`, `udiskie`, and post-boot hooks. [^23^]

### 6.5 FULL default keybinding set — VERBATIM

Bindings are declared via `o.bind("<KEYS>", "<description>", <dispatcher|string>, <opts>)`. Workspace keys use `code:NN` keycodes (`code:10`–`code:19` = digits 1–0; `code:20/21` = `-`/`=` row; `code:34/35` = `[`/`]`).

**`default/hypr/bindings/tiling.lua`** [^24^]

```lua
o.bind("SUPER + W", "Close window", hl.dsp.window.close())
o.bind("CTRL + ALT + DELETE", "Close all windows", "omarchy-hyprland-window-close-all")

o.bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
o.bind("SUPER + P", "Pseudo window", hl.dsp.window.pseudo())
o.bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
o.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("SUPER + CTRL + F", "Tiled full screen", "omarchy-hyprland-window-tiled-fullscreen-toggle")
o.bind("SUPER + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
o.bind("SUPER + O", "Pop window out (float & pin)", "omarchy-hyprland-window-pop")
o.bind("SUPER + ALT + Home", "Save window width", "omarchy-hyprland-window-width save")
o.bind("SUPER + Home", "Restore window width", "omarchy-hyprland-window-width restore")
o.bind("SUPER + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")

o.bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))
o.bind("SUPER + UP", "Focus on above window", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + DOWN", "Focus on below window", hl.dsp.focus({ direction = "d" }))

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

o.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
o.bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

o.bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
o.bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
o.bind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))

o.bind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
o.bind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
o.bind("SUPER + SHIFT + ALT + UP", "Move workspace to up monitor", hl.dsp.workspace.move({ monitor = "u" }))
o.bind("SUPER + SHIFT + ALT + DOWN", "Move workspace to down monitor", hl.dsp.workspace.move({ monitor = "d" }))

o.bind("SUPER + SHIFT + LEFT", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
o.bind("SUPER + SHIFT + RIGHT", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
o.bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

o.bind("ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind("ALT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind("ALT + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())

o.bind("CTRL + ALT + TAB", "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))
o.bind("CTRL + ALT + SHIFT + TAB", "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }))

o.bind("SUPER + code:20", "Expand window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
o.bind("SUPER + code:21", "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
o.bind("SUPER + SHIFT + code:20", "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
o.bind("SUPER + SHIFT + code:21", "Expand window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

o.bind("SUPER + ALT + code:20", "Expand window left a little", hl.dsp.window.resize({ x = -25, y = 0, relative = true }))
o.bind("SUPER + ALT + code:21", "Shrink window left a little", hl.dsp.window.resize({ x = 25, y = 0, relative = true }))
o.bind("SUPER + SHIFT + ALT + code:20", "Shrink window up a little", hl.dsp.window.resize({ x = 0, y = -25, relative = true }))
o.bind("SUPER + SHIFT + ALT + code:21", "Expand window down a little", hl.dsp.window.resize({ x = 0, y = 25, relative = true }))

o.bind("SUPER + CTRL + code:20", "Expand window left a lot", hl.dsp.window.resize({ x = -300, y = 0, relative = true }))
o.bind("SUPER + CTRL + code:21", "Shrink window left a lot", hl.dsp.window.resize({ x = 300, y = 0, relative = true }))
o.bind("SUPER + CTRL + SHIFT + code:20", "Shrink window up a lot", hl.dsp.window.resize({ x = 0, y = -300, relative = true }))
o.bind("SUPER + CTRL + SHIFT + code:21", "Expand window down a lot", hl.dsp.window.resize({ x = 0, y = 300, relative = true }))

o.bind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "e+1" }))
o.bind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "e-1" }))

o.bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
o.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

o.bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
o.bind("SUPER + ALT + G", "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))

o.bind("SUPER + ALT + LEFT", "Move window to group on left", hl.dsp.window.move({ into_group = "l" }))
o.bind("SUPER + ALT + RIGHT", "Move window to group on right", hl.dsp.window.move({ into_group = "r" }))
o.bind("SUPER + ALT + UP", "Move window to group on top", hl.dsp.window.move({ into_group = "u" }))
o.bind("SUPER + ALT + DOWN", "Move window to group on bottom", hl.dsp.window.move({ into_group = "d" }))

o.bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
o.bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())

o.bind("SUPER + CTRL + LEFT", "Move grouped window focus left", hl.dsp.group.prev())
o.bind("SUPER + CTRL + RIGHT", "Move grouped window focus right", hl.dsp.group.next())

o.bind("SUPER + ALT + mouse_down", "Next window in group", hl.dsp.group.next())
o.bind("SUPER + ALT + mouse_up", "Previous window in group", hl.dsp.group.prev())

for index = 1, 5 do
  o.bind("SUPER + ALT + code:" .. tostring(index + 9), "Switch to group window " .. index, hl.dsp.group.active({ index = index }))
end

o.bind("SUPER + SLASH", "Monitor scaling up", "omarchy-hyprland-monitor-scaling up")
o.bind("SUPER + ALT + SLASH", "Monitor scaling down", "omarchy-hyprland-monitor-scaling down")
```

**`default/hypr/bindings/applications.lua`** [^25^]

```lua
-- Essential application bindings.
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + SHIFT + RETURN", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + F", "File manager", { omarchy = "nautilus" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", { omarchy = "nautilus-cwd" })
o.bind("SUPER + SHIFT + B", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + ALT + B", "Browser (private)", { omarchy = "browser --private" })
o.bind("SUPER + SHIFT + N", "Editor", { omarchy = "editor" })

if o.preinstalled_bindings_enabled() then
  -- Bindings for preinstalled Omarchy applications, TUIs, and web apps.
  o.bind("SUPER + ALT + RETURN", "Tmux", { omarchy = "terminal-tmux" })
  o.bind("SUPER + SHIFT + M", "Music", { omarchy = "spotify" })
  o.bind("SUPER + SHIFT + ALT + M", "Music TUI", { tui = "cliamp", focus = true })
  o.bind("SUPER + SHIFT + D", "Docker", { tui = "lazydocker" })
  o.bind("SUPER + SHIFT + G", "Signal", { omarchy = "signal" })
  o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
  o.bind("SUPER + SHIFT + W", "Omawrite", { launch = "omawrite" })
  o.bind("SUPER + SHIFT + SLASH", "Passwords", { omarchy = "1password" })

  o.bind("SUPER + SHIFT + A", "ChatGPT", { webapp = "https://chatgpt.com" })
  o.bind("SUPER + SHIFT + ALT + A", "Grok", { webapp = "https://grok.com" })
  o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://app.hey.com/calendar/weeks/" })
  o.bind("SUPER + SHIFT + E", "Email", { webapp = "https://app.hey.com" })
  o.bind("SUPER + SHIFT + ALT + E", "New email", { webapp = "https://app.hey.com/messages/new?display=standalone&new_window=true" })
  o.bind("SUPER + SHIFT + Y", "YouTube", { webapp = "https://youtube.com/" })
  o.bind("SUPER + SHIFT + ALT + G", "WhatsApp", { webapp = "https://web.whatsapp.com/", focus = true })
  o.bind( "SUPER + SHIFT + CTRL + G", "Google Messages", { webapp = "https://messages.google.com/web/conversations", focus = true })
  o.bind("SUPER + SHIFT + P", "Google Photos", { webapp = "https://photos.google.com/", focus = true })
  o.bind("SUPER + SHIFT + S", "Google Maps", { webapp = "https://maps.google.com/", focus = true })
  o.bind("SUPER + SHIFT + X", "X", { webapp = "https://x.com/" })
  o.bind("SUPER + SHIFT + ALT + X", "X Post", { webapp = "https://x.com/compose/post" })
end
```

**`default/hypr/bindings/utilities.lua`** [^26^]

```lua
o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle")
o.bind("SUPER + CTRL + E", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
o.bind("SUPER + CTRL + C", "Capture menu", "omarchy-menu toggle capture")
o.bind("SUPER + CTRL + O", "Toggle menu", "omarchy-menu toggle toggle")
o.bind("SUPER + CTRL + H", "Hardware menu", "omarchy-menu toggle hardware")
o.bind("SUPER + SHIFT + code:201", "Omarchy menu", "omarchy-menu toggle root")
o.bind("SUPER + ESCAPE", "System menu", "omarchy-menu toggle system")
o.bind("XF86PowerOff", "Power menu", "omarchy-menu toggle system", { locked = true })
o.bind("SUPER + K", "Show key bindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + K", "Show Tmux key bindings", "omarchy-menu-tmux-keybindings")
o.bind("SUPER + CTRL + J", "Jump to waiting Tmux pane", "omarchy-tmux-alert focus")
o.bind("XF86Calculator", "Calculator", "gnome-calculator")

o.bind_toggle("SUPER + SHIFT + SPACE", "Toggle top bar", "bar")
o.bind("SUPER + CTRL + SPACE", "Background switcher", "omarchy-menu toggle background")
o.bind("SUPER + SHIFT + CTRL + SPACE", "Theme menu", "omarchy-menu toggle theme")
o.bind("SUPER + BACKSPACE", "Toggle window transparency", "omarchy-hyprland-window-transparency-toggle")
o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "omarchy-hyprland-window-gaps-toggle")
o.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", "omarchy-hyprland-window-single-square-aspect-toggle")

-- xkbcommon names the comma keysym "comma"; the upper-case "COMMA" does not match.
o.bind("SUPER + comma", "Dismiss last notification", "omarchy-shell notifications dismissOne")
o.bind("SUPER + SHIFT + comma", "Dismiss all notifications", "omarchy-shell notifications dismissAll")
o.bind_toggle("SUPER + CTRL + comma", "Toggle silencing notifications", "notification-silencing")
o.bind("SUPER + ALT + comma", "Invoke last notification", "omarchy-shell notifications invokeLast")
o.bind("SUPER + SHIFT + ALT + comma", "Open notification history", "omarchy-shell notifications showHistory")

o.bind_toggle("SUPER + CTRL + I", "Toggle locking on idle", "idle")
o.bind_toggle("SUPER + CTRL + N", "Toggle nightlight", "nightlight")
o.bind("SUPER + CTRL + Delete", "Toggle laptop display", "omarchy-hyprland-monitor-internal toggle")
o.bind("SUPER + CTRL + ALT + Delete", "Toggle laptop display mirroring", "omarchy-hyprland-monitor-internal-mirror toggle")
o.bind("switch:on:Lid Switch", nil, "omarchy-system-lid-close", { locked = true })
o.bind("switch:off:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell", { locked = true })

o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot")
o.bind("ALT + PRINT", "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord")
o.bind("SUPER + ALT + code:34", "Make webcam overlay smaller", "omarchy-capture-webcam-resize smaller")
o.bind("SUPER + ALT + code:35", "Make webcam overlay larger", "omarchy-capture-webcam-resize larger")
o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind("SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "omarchy-capture-text")

-- While the slurp region picker is open, Return captures the entire focused
-- monitor. The bind lives exactly as long as a selection layer is on screen
-- (slurp opens one per monitor), so it cannot leak or get stuck.
local selection_layers = 0

hl.on("layer.opened", function(layer)
  if layer.namespace == "selection" then
    selection_layers = selection_layers + 1
    if selection_layers == 1 then
      hl.bind("RETURN", hl.dsp.exec_cmd("omarchy-capture-region --take-fullscreen"), { description = "Capture entire screen" })
    end
  end
end)

hl.on("layer.closed", function(layer)
  if layer.namespace == "selection" and selection_layers > 0 then
    selection_layers = selection_layers - 1
    if selection_layers == 0 then
      hl.unbind("RETURN")
    end
  end
end)

o.bind("SUPER + CTRL + S", "Share", "omarchy-menu toggle share")

o.bind("SUPER + CTRL + PERIOD", "Transcode", "omarchy-transcode")

o.bind("SUPER + CTRL + R", "Set reminder", "omarchy-menu toggle reminder-set")
o.bind("SUPER + CTRL + ALT + R", "Show reminders", "omarchy-reminder show")
o.bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "omarchy-reminder clear")

o.bind("SUPER + CTRL + ALT + T", "Show time", "omarchy-notification-time")
o.bind("SUPER + CTRL + ALT + B", "Show battery remaining", "omarchy-notification-battery")
o.bind("SUPER + CTRL + ALT + W", "Toggle weather", "omarchy-notification-weather")

o.bind("SUPER + CTRL + A", "Audio", "omarchy-shell shell toggle omarchy.audio")
o.bind("SUPER + CTRL + B", "Bluetooth", "omarchy-shell shell toggle omarchy.bluetooth")
o.bind("SUPER + CTRL + D", "Display", "omarchy-shell shell toggle omarchy.monitor")
o.bind("SUPER + CTRL + W", "Network", "omarchy-shell shell toggle omarchy.network")
o.bind("SUPER + CTRL + P", "Power", "omarchy-shell shell toggle omarchy.power")
o.bind("SUPER + CTRL + T", "Activity", { tui = "btop" })

o.bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)

o.bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

o.bind("SUPER + CTRL + L", "Lock system", "omarchy-system-lock")
```

**`default/hypr/bindings/media.lua`** [^27^]

```lua
-- Volume, brightness, keyboard backlight, and touchpad controls.
o.bind("XF86AudioRaiseVolume", "Volume up", "omarchy-audio-output-volume raise", { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Volume down", "omarchy-audio-output-volume lower", { locked = true, repeating = true })
o.bind("XF86AudioMute", "Mute", "omarchy-audio-output-volume mute-toggle", { locked = true })
o.bind("XF86AudioMicMute", "Mute microphone", "omarchy-audio-input-mute", { locked = true })
o.bind("XF86MonBrightnessUp", "Brightness up", "omarchy-brightness-display +5%", { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Brightness down", "omarchy-brightness-display 5%-", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessUp", "Brightness maximum", "omarchy-brightness-display 100%", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "omarchy-brightness-display 1%", { locked = true, repeating = true })
o.bind("XF86KbdBrightnessUp", "Keyboard brightness up", "omarchy-brightness-keyboard up", { locked = true, repeating = true })
o.bind("XF86KbdBrightnessDown", "Keyboard brightness down", "omarchy-brightness-keyboard down", { locked = true, repeating = true })
o.bind("XF86KbdLightOnOff", "Keyboard backlight cycle", "omarchy-brightness-keyboard cycle", { locked = true })
o.bind_toggle("XF86TouchpadToggle", "Toggle touchpad", "touchpad", { locked = true })
o.bind("XF86TouchpadOn", "Enable touchpad", "omarchy-toggle-touchpad on", { locked = true })
o.bind("XF86TouchpadOff", "Disable touchpad", "omarchy-toggle-touchpad off", { locked = true })

-- Precise volume and brightness controls.
o.bind("ALT + XF86AudioRaiseVolume", "Volume up precise", "omarchy-audio-output-volume +1", { locked = true, repeating = true })
o.bind("ALT + XF86AudioLowerVolume", "Volume down precise", "omarchy-audio-output-volume -1", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", "omarchy-brightness-display +1%", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", "omarchy-brightness-display 1%-", { locked = true, repeating = true })

-- Media controls.
o.bind("XF86AudioNext", "Next track", "omarchy-shell media next", { locked = true })
o.bind("ALT + XF86AudioPlay", "Next track", "omarchy-shell media next", { locked = true })
o.bind("XF86AudioPause", "Pause", "omarchy-shell media playPause", { locked = true })
o.bind("XF86AudioPlay", "Play", "omarchy-shell media playPause", { locked = true })
o.bind("XF86AudioPrev", "Previous track", "omarchy-shell media previous", { locked = true })
o.bind("ALT + SHIFT + XF86AudioPlay", "Previous track", "omarchy-shell media previous", { locked = true })

o.bind("SHIFT + XF86AudioMute", "Switch audio output", "omarchy-audio-output-switch", { locked = true })
o.bind("SHIFT + XF86AudioPause", "Switch media source", "omarchy-audio-source-switch", { locked = true })
o.bind("SHIFT + XF86AudioPlay", "Switch media source", "omarchy-audio-source-switch", { locked = true })
```

**`default/hypr/bindings/clipboard.lua`** (key lines — universal SUPER+C/V/X copy/paste/cut that adapts to terminals via `hl.dsp.send_key_state`) [^28^]

```lua
o.bind("SUPER + C", "Universal copy", universal_clipboard_shortcut("CTRL", "C", "CTRL", "Insert"))
o.bind("SUPER + V", "Universal paste", universal_clipboard_shortcut("CTRL", "V", "SHIFT", "Insert"))
o.bind("SUPER + X", "Universal cut", send_shortcut_once("CTRL", "X"))
o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
```

**`default/hypr/bindings/voxtype.lua`** (only if `voxtype` dictation binary present) [^29^]

```lua
if o.cmd_present("voxtype") then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")
  o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")
  o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
end
```

## 7. Themes

**22 bundled themes** under `themes/` [^2^]:

`catppuccin`, `catppuccin-latte`, `ethereal`, `everforest`, `flexoki-light`, `gruvbox`, `hackerman`, `kanagawa`, `last-horizon`, `lumon`, `lupine`, `matte-black`, `miasma`, `nord`, `osaka-jade`, `retro-82`, `ristretto`, `rose-pine`, `solitude`, `tokyo-night`, `vantablack`, `white`

Each theme dir contains: **`colors.toml`** (the single source of truth palette), `backgrounds/` (1–9 wallpapers), `icons.theme` (icon set, e.g. Yaru colors), `preview.png` / `preview-unlock.png` / `unlock.png` (menu + SDDM/lock previews), and optional overrides: `hyprland.lua` (border colors — kanagawa, last-horizon, lumon, retro-82, solitude), `btop.theme`, `chromium.theme`, `keyboard.rgb` (tokyo-night), `neovim.lua`, `vscode.json`. [^2^][^36^]

**Theme application pipeline:** `omarchy-theme-set` renders the templates in `default/themed/` against `colors.toml` into `~/.local/state/omarchy/current/theme/`. Templates shipped [^49^]: `alacritty.toml.tpl`, `btop.theme.tpl`, `chromium.theme.tpl`, `foot.ini.tpl`, `ghostty.conf.tpl`, `gum_env.lua.tpl`, `helix.toml.tpl`, `hyprland-preview-share-picker.css.tpl`, `hyprland.lua.tpl`, `keyboard.rgb.tpl`, `kitty.conf.tpl`, `neovim.lua.tpl`, `obsidian.css.tpl`, `pi.json.tpl`, `shell.toml.tpl` (the Quickshell theme), `vscode-theme.json.tpl`. Per-app setters: `omarchy-theme-set-{browser,foot,gnome,keyboard,obsidian,pi,tmux,vscode}` plus Plymouth sync (`omarchy-plymouth-set-by-theme`). [^2^]

### 7.1 Palette schema (`colors.toml`)

Every palette uses the same 25-key schema: `mode`, `accent`, `selection`, `muted`, 4 background shades, 4 foreground shades, 8 normal colors (`red yellow orange green cyan blue magenta brown`), 6 bright colors. Verbatim palettes (repo path `themes/<name>/colors.toml`) [^36^]:

**tokyo-night** — `themes/tokyo-night/colors.toml`
```toml
mode = "dark"

accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"

foreground = "#a9b1d6"
dark_foreground = "#565f89"
light_foreground = "#b4bee6"
bright_foreground = "#c0caf5"

red = "#f7768e"
yellow = "#e0af68"
orange = "#eb927b"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
brown = "#75493d"

bright_red = "#ff7a93"
bright_yellow = "#ff9e64"
bright_green = "#b9f27c"
bright_cyan = "#0db9d7"
bright_blue = "#7da6ff"
bright_magenta = "#bb9af7"
```

**catppuccin** — `themes/catppuccin/colors.toml`
```toml
mode = "dark"

accent = "#89b4fa"
selection = "#45475a"
muted = "#585b70"

background = "#1e1e2e"
dark_background = "#161622"
darker_background = "#101019"
lighter_background = "#313244"

foreground = "#cdd6f4"
dark_foreground = "#6c7086"
light_foreground = "#bac2de"
bright_foreground = "#cdd6f4"

red = "#f38ba8"
yellow = "#f9e2af"
orange = "#f6b6ab"
green = "#a6e3a1"
cyan = "#94e2d5"
blue = "#89b4fa"
magenta = "#f5c2e7"
brown = "#7b5b55"

bright_red = "#f38ba8"
bright_yellow = "#f9e2af"
bright_green = "#a6e3a1"
bright_cyan = "#94e2d5"
bright_blue = "#89b4fa"
bright_magenta = "#f5c2e7"
```

**gruvbox** — `themes/gruvbox/colors.toml`
```toml
mode = "dark"

accent = "#7daea3"
selection = "#504945"
muted = "#665c54"

background = "#282828"
dark_background = "#1e1e1e"
darker_background = "#161616"
lighter_background = "#3c3836"

foreground = "#d4be98"
dark_foreground = "#7c6f64"
light_foreground = "#bdae93"
bright_foreground = "#d4be98"

red = "#ea6962"
yellow = "#d8a657"
orange = "#e1875c"
green = "#a9b665"
cyan = "#89b482"
blue = "#7daea3"
magenta = "#d3869b"
brown = "#70432e"

bright_red = "#ea6962"
bright_yellow = "#d8a657"
bright_green = "#a9b665"
bright_cyan = "#89b482"
bright_blue = "#7daea3"
bright_magenta = "#d3869b"
```

**nord** — `themes/nord/colors.toml`
```toml
mode = "dark"

accent = "#81a1c1"
selection = "#434c5e"
muted = "#4c566a"

background = "#2e3440"
dark_background = "#222730"
darker_background = "#191c23"
lighter_background = "#3b4252"

foreground = "#d8dee9"
dark_foreground = "#667080"
light_foreground = "#adb5c4"
bright_foreground = "#d8dee9"

red = "#bf616a"
yellow = "#ebcb8b"
orange = "#d5967a"
green = "#a3be8c"
cyan = "#88c0d0"
blue = "#81a1c1"
magenta = "#b48ead"
brown = "#6a4b3d"

bright_red = "#bf616a"
bright_yellow = "#ebcb8b"
bright_green = "#a3be8c"
bright_cyan = "#8fbcbb"
bright_blue = "#81a1c1"
bright_magenta = "#b48ead"
```

**everforest** — `themes/everforest/colors.toml`
```toml
mode = "dark"

accent = "#7fbbb3"
selection = "#3d484d"
muted = "#475258"

background = "#2d353b"
dark_background = "#21272c"
darker_background = "#181d20"
lighter_background = "#343f44"

foreground = "#d3c6aa"
dark_foreground = "#4f585e"
light_foreground = "#9da9a0"
bright_foreground = "#d3c6aa"

red = "#e67e80"
yellow = "#dbbc7f"
orange = "#e09d7f"
green = "#a7c080"
cyan = "#83c092"
blue = "#7fbbb3"
magenta = "#d699b6"
brown = "#704e3f"

bright_red = "#e67e80"
bright_yellow = "#dbbc7f"
bright_green = "#a7c080"
bright_cyan = "#83c092"
bright_blue = "#7fbbb3"
bright_magenta = "#d699b6"
```

**osaka-jade** — `themes/osaka-jade/colors.toml`
```toml
mode = "dark"

accent = "#509475"
selection = "#32473B"
muted = "#53685B"

background = "#111c18"
dark_background = "#0c1512"
darker_background = "#090f0d"
lighter_background = "#23372B"

foreground = "#C1C497"
dark_foreground = "#81B8A8"
light_foreground = "#D6D5BC"
bright_foreground = "#F7E8B2"

red = "#FF5345"
yellow = "#459451"
orange = "#a2734b"
green = "#549e6a"
cyan = "#2DD5B7"
blue = "#509475"
magenta = "#D2689C"
brown = "#513925"

bright_red = "#db9f9c"
bright_yellow = "#E5C736"
bright_green = "#63b07a"
bright_cyan = "#8CD3CB"
bright_blue = "#ACD4CF"
bright_magenta = "#75bbb3"
```

**ristretto** — `themes/ristretto/colors.toml`
```toml
mode = "dark"

accent = "#f38d70"
selection = "#403e41"
muted = "#72696a"

background = "#2c2525"
dark_background = "#211b1b"
darker_background = "#181414"
lighter_background = "#3d2f2a"

foreground = "#e6d9db"
dark_foreground = "#72696a"
light_foreground = "#c3b7b8"
bright_foreground = "#e6d9db"

red = "#fd6883"
yellow = "#f9cc6c"
orange = "#fb9a77"
green = "#adda78"
cyan = "#85dacc"
blue = "#f38d70"
magenta = "#a8a9eb"
brown = "#7d4d3b"

bright_red = "#ff8297"
bright_yellow = "#fcd675"
bright_green = "#c8e292"
bright_cyan = "#9bf1e1"
bright_blue = "#f8a788"
bright_magenta = "#bebffd"
```

## 8. `bin/` — the complete `omarchy-*` command catalog (380 scripts)

`bin/omarchy` is the router CLI (`omarchy <group> <verb>`); every script carries `# omarchy:summary=` metadata (extracted verbatim below). Official group descriptions from `bin/omarchy` `GROUP_DESCRIPTIONS` [^37^][^9^]:


- **audio** — Audio input and output controls
- **bar** — Omarchy shell bar layout and settings
- **battery** — Battery status helpers
- **bluetooth** — Bluetooth device controls
- **branch** — Omarchy git branch management
- **branding** — About and screensaver branding
- **brightness** — Display and keyboard brightness
- **capture** — Screenshots and screen recording
- **channel** — Omarchy release channel management
- **clipboard** — Clipboard helpers
- **cmd** — Command and shortcut helpers
- **config** — System configuration helpers
- **debug** — Diagnostics and support logs
- **finalize** — Finalize user setup
- **default** — Default application selection
- **dev** — Omarchy development tools
- **display** — Display and text scaling
- **dns** — DNS resolver configuration
- **drive** — Drive selection and encryption
- **font** — Font management
- **games** — Game launchers and helpers
- **hibernation** — Hibernation setup and removal
- **hook** — User hook runner
- **hw** — Hardware detection and controls
- **hyprland** — Hyprland window, monitor, and toggle controls
- **install** — Optional software installers
- **installed** — Installed optional service checks
- **launch** — Application launchers
- **menu** — Omarchy menu commands
- **migrate** — Migration runner
- **monitor** — Monitor status helpers
- **network** — Network status helpers
- **notification** — Notification helpers
- **mise** — Mise tool wrappers
- **osd** — On-screen display status helpers
- **pkg** — Package management helpers
- **plugin** — Omarchy shell plugin and bar widget management
- **plymouth** — Plymouth boot theme management
- **power** — Power supply detection
- **powerprofiles** — Power profile management
- **refresh** — Reset config to defaults
- **reinstall** — Reinstall and reset workflows
- **reminder** — Desktop notification reminders
- **remove** — Removal workflows
- **restart** — Restart Omarchy components
- **setup** — Interactive setup wizards
- **shell** — Omarchy shell IPC helpers
- **screensaver** — Screensaver branding and animation
- **snapshot** — System snapshots
- **style** — Global UI style controls
- **sudo** — Sudo configuration helpers
- **system** — System status, reboot, shutdown, logout, and lock
- **theme** — Theme management
- **tmux** — Tmux session helpers
- **toggle** — Toggle Omarchy features
- **transcode** — Image and video transcoding
- **tui** — Terminal UI launchers
- **tz** — Timezone selection
- **update** — Omarchy and system updates
- **version** — Version and channel information
- **voxtype** — Voxtype dictation
- **weather** — Weather status
- **webapp** — Web app launchers
- **wifi** — Wi-Fi helpers
- **windows** — Windows VM management
-e 
Full catalog, grouped (name — verbatim `# omarchy:summary=`):

### `(root)` (20)
- `omarchy` — (no summary metadata)
- `omarchy-bar` — Set the active bar option, position, and transparency
- `omarchy-debug` — Print debugging information
- `omarchy-dns` — Show or configure the system DNS provider
- `omarchy-done` — Check or mark completed Omarchy setup tasks
- `omarchy-hook` — Run a named hook from ~/.config/omarchy/hooks/<name> and ~/.config/omarchy/hooks/<name>.d/.
- `omarchy-menu` — Control the Omarchy menu (toggle / summon / close / refresh)
- `omarchy-migrate` — Run pending Omarchy migrations.
- `omarchy-osd` — Show the Omarchy Quickshell on-screen display
- `omarchy-plugin` — Manage Omarchy shell plugins and bar widgets
- `omarchy-reinstall` — Reinstall Omarchy packages and reset default configs
- `omarchy-reminder` — Set and show lightweight desktop notification reminders
- `omarchy-screensaver` — Run the Omarchy screensaver using random effects from TTE.
- `omarchy-shell` — Send an IPC call to the running Omarchy shell
- `omarchy-snapshot` — Create or restore system snapshots with snapper
- `omarchy-state` — Manage persistent state files for Omarchy toggles and settings.
- `omarchy-toggle` — Toggle Omarchy features between enabled and disabled
- `omarchy-transcode` — Transcode pictures and videos for sharing
- `omarchy-update` — Update Omarchy and system packages
- `omarchy-version` — Print the installed Omarchy version

### `audio` (9)
- `omarchy-audio-input-mute` — Toggle microphone mute. Drives the hardware mic-mute LED on laptops that expose one.
- `omarchy-audio-input-set-default` — Set the default audio input and move active streams
- `omarchy-audio-output-set-default` — Set the default audio output and move active streams
- `omarchy-audio-output-sink` — Print the sink whose volume and mute a given output really uses
- `omarchy-audio-output-switch` — Switch between audio outputs while preserving the mute status
- `omarchy-audio-output-volume` — Adjust output volume and show the Omarchy OSD
- `omarchy-audio-sink-availability` — Print PulseAudio sink availability for the shell
- `omarchy-audio-source-switch` — Cycle to the next media source and transfer playback when the current source is playing
- `omarchy-audio-tuning` — Manage the speaker tuning for this laptop

### `bar` (2)
- `omarchy-bar-plugin` — Add, move, remove, and configure bar plugin widgets in the layout
- `omarchy-bar-text-color` — Choose a legible transparent bar text color

### `battery` (3)
- `omarchy-battery-low` — Send the low battery warning notification and run battery-low hooks.
- `omarchy-battery-present` — Returns true if a battery is present on the system.
- `omarchy-battery-status` — Returns a formatted battery status string with percentage and power draw/charge.

### `bluetooth` (1)
- `omarchy-bluetooth-device` — Control a Bluetooth device

### `branding` (2)
- `omarchy-branding-about` — Edit, set, or reset About branding
- `omarchy-branding-screensaver` — Edit, set, or reset screensaver branding

### `brightness` (4)
- `omarchy-brightness-display` — Show or adjust brightness on the most likely display device.
- `omarchy-brightness-display-apple` — Show or adjust Apple Studio Display and Apple XDR Display brightness using asdcontrol.
- `omarchy-brightness-keyboard` — Adjust keyboard backlight brightness using available steps.
- `omarchy-brightness-keyboard-mute` — Set the mic-mute indicator LED on laptops that expose a platform::micmute LED node.

### `capture` (6)
- `omarchy-capture-region` — Pick a screen region over frozen screen content
- `omarchy-capture-screenrecording` — Start or stop screen recording
- `omarchy-capture-screenrecording-with-webcam` — Pick a webcam and start a screen recording with it
- `omarchy-capture-screenshot` — Take a screenshot
- `omarchy-capture-text` — Extract text from a screenshot region with OCR
- `omarchy-capture-webcam-resize` — Resize the active webcam recording overlay

### `channel` (2)
- `omarchy-channel-current` — Print the active Omarchy package channel
- `omarchy-channel-set` — Set the Omarchy package channel.

### `chromium` (2)
- `omarchy-chromium-copy-url-host` — Native messaging host: copy a Chromium tab URL to the clipboard
- `omarchy-chromium-ytdlp-host` — Native messaging host: download the URL sent by the yt-dlp Chromium extension

### `clipboard` (3)
- `omarchy-clipboard-open` — Open a clipboard history entry
- `omarchy-clipboard-paste-file` — Copy a file to the clipboard and paste it
- `omarchy-clipboard-paste-text` — Copy text to the clipboard and type or paste it

### `cmd` (3)
- `omarchy-cmd-missing` — Check whether any required commands are missing
- `omarchy-cmd-present` — Check whether all required commands are available
- `omarchy-cmd-terminal-cwd` — Print the current working directory of the active terminal window

### `debug` (1)
- `omarchy-debug-idle` — Show idle, screensaver, and lock diagnostics

### `default` (3)
- `omarchy-default-browser` — Set the default browser for Omarchy and XDG handlers
- `omarchy-default-editor` — Set the default editor used by omarchy-launch-editor
- `omarchy-default-terminal` — Set the default terminal used by xdg-terminal-exec

### `dev` (10)
- `omarchy-dev-add-migration` — Create a new Omarchy migration in the current source tree.
- `omarchy-dev-benchmark-cli` — Measure Omarchy CLI response times
- `omarchy-dev-benchmark-theme-switcher` — Measure theme switcher cache and selector prep times
- `omarchy-dev-install-ydoo` — Install and enable ydotool mouse automation for Omarchy development
- `omarchy-dev-link` — Point Omarchy at a local checkout after reboot
- `omarchy-dev-pkg-test` — Build and install an Omarchy package from a local checkout
- `omarchy-dev-status` — Show the current Omarchy dev-link state
- `omarchy-dev-theme-preview` — Preview an Omarchy theme palette in the terminal
- `omarchy-dev-ui-preview` — Open the omarchy-shell dev gallery (qs.Ui kit preview)
- `omarchy-dev-unlink` — Restore Omarchy to the package install after reboot

### `display` (1)
- `omarchy-display-text-size` — Scale text everywhere — omarchy shell, GTK apps, and terminals

### `drive` (3)
- `omarchy-drive-info` — Print drive information such as size, model, and mount details
- `omarchy-drive-password` — Set a new encryption password for a drive selected.
- `omarchy-drive-select` — Select a drive from a list with info that includes space and brand. Used by omarchy-drive-password.

### `finalize` (1)
- `omarchy-finalize-user` — Finalize Omarchy user setup (runtime tweaks /etc/skel can't do)

### `first` (1)
- `omarchy-first-run` — Finish first-login setup for Omarchy.

### `font` (3)
- `omarchy-font-current` — Show current monospace font
- `omarchy-font-list` — List available monospace fonts
- `omarchy-font-set` — Set the system monospace font

### `games` (2)
- `omarchy-games-retro-cores` — List installed RetroArch core names
- `omarchy-games-retro-install` — Create a desktop launcher for a RetroArch game

### `hibernation` (3)
- `omarchy-hibernation-available` — Check if hibernation is supported
- `omarchy-hibernation-remove` — Remove hibernation setup including swap and boot resume settings
- `omarchy-hibernation-setup` — Set up hibernation with swap and boot resume configuration

### `hook` (1)
- `omarchy-hook-install` — Install a hook into ~/.config/omarchy/hooks/<type>.d/

### `hw` (26)
- `omarchy-hw-asus-expertbook-b9406` — Detect ASUS ExpertBook B9406 series laptops on Intel Panther Lake.
- `omarchy-hw-asus-rog` — Detect whether the computer is an Asus ROG machine.
- `omarchy-hw-asus-zenbook-ux5406aa` — Detect ASUS Zenbook UX5406AA series laptops on Intel Panther Lake.
- `omarchy-hw-clamshell` — Returns true when clamshell mode is active
- `omarchy-hw-dell-xps-haptic-touchpad` — Match Dell XPS systems with the Synaptics haptic touchpad.
- `omarchy-hw-dell-xps-oled` — Match Dell XPS systems with LG OLED panel on Intel Panther Lake (Xe3) GPU.
- `omarchy-hw-display` — Print the most likely display backlight device.
- `omarchy-hw-external-monitors` — Returns true when an external monitor is physically connected.
- `omarchy-hw-fingerprint` — Returns true when a fingerprint reader is present
- `omarchy-hw-framework16` — Detect whether the computer is a Framework Laptop 16.
- `omarchy-hw-hybrid-gpu` — Detect whether the system has an active hybrid GPU configuration
- `omarchy-hw-intel` — Detect whether the computer has an Intel CPU.
- `omarchy-hw-intel-ptl` — Detect whether the computer has an Intel Panther Lake GPU.
- `omarchy-hw-intel-sof` — Detect an Intel SOF-capable audio DSP
- `omarchy-hw-laptop` — Returns true when running on a laptop (has a lid or laptop chassis).
- `omarchy-hw-laptop-closed` — Returns true when the laptop lid is closed
- `omarchy-hw-match` — Match against the computer's DMI product name or product family (case-insensitive).
- `omarchy-hw-nvidia` — Detect whether the computer has an NVIDIA GPU.
- `omarchy-hw-nvidia-gsp` — Detect whether the computer has an NVIDIA GPU with GSP firmware (Turing or newer).
- `omarchy-hw-nvidia-without-gsp` — Detect whether the computer has an NVIDIA GPU without GSP firmware (Maxwell/Pascal/Volta).
- `omarchy-hw-recover-internal-monitor` — Clear the internal-monitor-disable toggle if no external display is connected.
- `omarchy-hw-surface` — Detect whether the computer is a Microsoft Surface device.
- `omarchy-hw-touchpad` — Print the detected Hyprland touchpad or trackpad device name
- `omarchy-hw-touchscreen` — Print the detected Hyprland touchscreen or tablet device name
- `omarchy-hw-vulkan` — Detect whether Vulkan is available.
- `omarchy-hw-webcam` — Check whether a webcam is available

### `hyprland` (22)
- `omarchy-hyprland-focus-app` — Focus a Hyprland window by application class
- `omarchy-hyprland-monitor-clamshell` — Apply clamshell display state to Hyprland monitors
- `omarchy-hyprland-monitor-external-active` — Returns true when Hyprland has an active external monitor
- `omarchy-hyprland-monitor-focused` — Print the name of the currently focused Hyprland monitor.
- `omarchy-hyprland-monitor-focused-apple` — Return success if the focused Hyprland monitor is an Apple display.
- `omarchy-hyprland-monitor-internal` — Enable, disable, toggle, or recover the internal laptop display
- `omarchy-hyprland-monitor-internal-mirror` — Enable, disable, toggle, or recover mirroring the internal display to an external monitor
- `omarchy-hyprland-monitor-laptop` — Print the name of the built-in laptop display, including disabled outputs.
- `omarchy-hyprland-monitor-scaling` — Show, set, or adjust focused Hyprland monitor scaling
- `omarchy-hyprland-monitor-watch` — Watch Hyprland monitor events and recover monitor toggles when a monitor is removed
- `omarchy-hyprland-reload-guard` — Pause or resume Hyprland config auto-reload around package transactions.
- `omarchy-hyprland-toggle` — Toggle permanent Hyprland flags by copying them into a directory that's sourced entirely.
- `omarchy-hyprland-toggle-disabled` — Check if a Hyprland toggle is currently disabled (missing).
- `omarchy-hyprland-toggle-enabled` — Check if a Hyprland toggle is currently enabled.
- `omarchy-hyprland-window-close-all` — Close all open windows
- `omarchy-hyprland-window-gaps-toggle` — Toggles the window gaps globally between no gaps and the default.
- `omarchy-hyprland-window-pop` — Toggle to pop-out a tile to stay fixed on a display basis.
- `omarchy-hyprland-window-single-square-aspect-toggle` — Toggle single-window square aspect ratio.
- `omarchy-hyprland-window-tiled-fullscreen-toggle` — Toggle tiled fullscreen for the focused Hyprland window
- `omarchy-hyprland-window-transparency-toggle` — Toggles transparency for the currently focused window.
- `omarchy-hyprland-window-width` — Save or restore the focused Hyprland window width
- `omarchy-hyprland-workspace-layout-toggle` — Toggle the layout on the current active workspace between dwindle and scrolling

### `install` (31)
- `omarchy-install-and-launch` — Install a packaged app and gtk-launch it once it finishes
- `omarchy-install-app` — Install a packaged app, surfacing the install in a floating terminal
- `omarchy-install-browser` — Install a supported browser
- `omarchy-install-chromium-copy-url` — Install the native messaging host for the Copy URL Chromium extension
- `omarchy-install-chromium-google-account` — Allow Chromium to sign in to Google accounts by adding the required OAuth credentials
- `omarchy-install-chromium-ytdlp` — Install the native messaging host for the yt-dlp Chromium extension
- `omarchy-install-dev-env` — Install a supported development environment
- `omarchy-install-docker-dbs` — Install one of the supported databases in a Docker container with the suitable development options.
- `omarchy-install-editor-emacs` — Install Emacs with Omarchy theme and font integration via the omarchy-emacs AUR package
- `omarchy-install-editor-helix` — Install Helix and configure it to use the current Omarchy theme
- `omarchy-install-editor-vscode` — Install VS Code and configure Omarchy defaults for secrets, updates, and theme
- `omarchy-install-editor-zed` — Install Zed Editor and configure it with the current Omarchy theme
- `omarchy-install-font` — Install a Nerd Font package and switch the system to it
- `omarchy-install-gaming-battlenet` — Install Battle.net standalone via umu-launcher + GE-Proton (no Steam, no Lutris, no Heroic).
- `omarchy-install-gaming-geforce-now` — Install and launch Geforce Now.
- `omarchy-install-gaming-gpu-lib32` — Install lib32 graphics drivers (Vulkan + NVIDIA) for any detected GPUs.
- `omarchy-install-gaming-heroic` — Install Heroic Games Launcher (Epic, GOG, Amazon Prime Gaming) with graphics drivers.
- `omarchy-install-gaming-lutris` — Install Lutris with Wine + DXVK for running Windows games (Battle.net, EA, Ubisoft Connect, etc.)
- `omarchy-install-gaming-retroarch` — Install RetroArch with the full libretro core set plus FBNeo and a ~/Games ROM directory.
- `omarchy-install-gaming-steam` — Install Steam and graphics drivers selected for this system
- `omarchy-install-gaming-xbox-cloud` — Install Xbox Cloud Gaming as a web app and launch it.
- `omarchy-install-gaming-xbox-controllers` — Install support for using Xbox controllers with Steam/RetroArch/etc.
- `omarchy-install-service-1password` — Install 1Password and its Chromium extension.
- `omarchy-install-service-dropbox` — Install and start the Dropbox service. Must then be authenticated via the web.
- `omarchy-install-service-nordvpn` — Install the NordVPN service with optional GUI.
- `omarchy-install-service-once` — Install the ONCE service, enable its background service, and launch the TUI.
- `omarchy-install-service-signal` — Install Signal and launch it.
- `omarchy-install-service-spotify` — Install Spotify.
- `omarchy-install-service-sunshine` — Install Sunshine and open Moonlight streaming ports for LAN and Tailscale.
- `omarchy-install-service-tailscale` — Install the Tailscale mesh VPN service and a web app for the Tailscale Admin Console.
- `omarchy-install-terminal` — Install one of the approved terminals and set it as the default for Omarchy (Super + Return etc).

### `installed` (2)
- `omarchy-installed-service-dropbox` — Check whether Dropbox is installed and running
- `omarchy-installed-service-tailscale` — Check whether Tailscale is installed and running

### `launch` (19)
- `omarchy-launch-1password` — Launch 1Password or start its installer when missing.
- `omarchy-launch-about` — Launch the fastfetch TUI that gives information about the current system.
- `omarchy-launch-battlenet` — Launch the installed Battle.net client via umu-launcher + GE-Proton.
- `omarchy-launch-browser` — Launch the default browser as determined by xdg-settings.
- `omarchy-launch-config-editor` — Open a config file in the user's editor and surface a toast
- `omarchy-launch-editor` — Launch the default editor selected via Omarchy defaults.
- `omarchy-launch-floating-terminal-with-presentation` — Launch a floating terminal with the Omarchy presentation wrapper
- `omarchy-launch-nautilus` — Launch Files
- `omarchy-launch-nautilus-cwd` — Launch Files in the active terminal's current directory
- `omarchy-launch-or-focus` — Launch an app or focus an existing window matching a pattern
- `omarchy-launch-or-focus-tui` — Launch a TUI or focus an existing terminal window for it
- `omarchy-launch-or-focus-webapp` — Launch or focus on a given web app identified by the window-pattern.
- `omarchy-launch-screensaver` — Launch the Omarchy screensaver in the default terminal on the system with the correct font configuration.
- `omarchy-launch-signal` — Launch Signal or start its installer when missing.
- `omarchy-launch-spotify` — Launch Spotify or start its installer when missing.
- `omarchy-launch-terminal` — Launch a terminal in the active terminal's current directory
- `omarchy-launch-terminal-tmux` — Launch or attach to the Work tmux session in a terminal
- `omarchy-launch-tui` — Launch a TUI command in the default terminal with Omarchy styling
- `omarchy-launch-webapp` — Launch a URL as a web app in the default supported browser

### `menu` (11)
- `omarchy-menu-clipboard` — Launch the clipboard manager
- `omarchy-menu-emoji` — Launch emojis
- `omarchy-menu-emoji-insert` — Insert an emoji into the focused application
- `omarchy-menu-file` — Pick a file from a menu
- `omarchy-menu-images` — Open a generic image selector menu
- `omarchy-menu-input` — Prompt for text input from a menu
- `omarchy-menu-keybindings` — Display Hyprland keybindings defined in your configuration using an interactive search menu.
- `omarchy-menu-select` — Pick one option from a menu
- `omarchy-menu-share` — Share clipboard, files, or folders with LocalSend
- `omarchy-menu-timezone` — Select and set the system timezone
- `omarchy-menu-tmux-keybindings` — Display annotated Tmux keybindings using an interactive search menu.

### `migrate` (1)
- `omarchy-migrate-notify` — Notify the user when Omarchy has pending migrations

### `mise` (1)
- `omarchy-mise-install` — Install a small mise-backed wrapper for a given tool.

### `monitor` (1)
- `omarchy-monitor-state` — Print monitor panel state for the shell

### `network` (2)
- `omarchy-network-speedtest` — Measure live internet speed for one direction
- `omarchy-network-status` — Print active network status for the shell

### `notification` (6)
- `omarchy-notification-battery` — Show the current battery status notification
- `omarchy-notification-dismiss` — Dismiss a notification by summary substring. Used by the first-run notifications to dismiss them after clicking for action.
- `omarchy-notification-send` — Send an Omarchy desktop notification
- `omarchy-notification-time` — Show the current time and date notification
- `omarchy-notification-wait` — Wait for the desktop notification server to accept notifications
- `omarchy-notification-weather` — Toggle the current weather panel

### `pkg` (9)
- `omarchy-pkg-add` — Install Arch packages if they are missing
- `omarchy-pkg-aur-accessible` — Returns true if the AUR is up and available.
- `omarchy-pkg-aur-add` — Add the named packages to the system from the AUR if they're missing. Returns false if it couldn't be done.
- `omarchy-pkg-aur-install` — Show a fuzzy-finder TUI for picking new AUR packages to install.
- `omarchy-pkg-drop` — Remove all the named packages from the system if they're installed (otherwise ignore).
- `omarchy-pkg-install` — Show a fuzzy-finder TUI for picking new Arch and OPR packages to install.
- `omarchy-pkg-missing` — Returns true if any of the named packages are missing from the system (or false if they're all there).
- `omarchy-pkg-present` — Returns true if all of the named packages are installed on the system (or false if any of them are missing).
- `omarchy-pkg-remove` — Show a fuzzy-finder TUI for picking packages installed on the system to be removed.

### `plugin` (3)
- `omarchy-plugin-catalog` — Emit every first-party and user plugin manifest as JSON
- `omarchy-plugin-clone` — Clone a built-in or user Omarchy shell plugin into your own config
- `omarchy-plugin-validate` — Validate a plugin folder against the Omarchy plugin manifest schema

### `plymouth` (7)
- `omarchy-plymouth-current` — Show which theme is styling the Plymouth boot screen
- `omarchy-plymouth-list` — List themes that can style the Plymouth boot screen
- `omarchy-plymouth-preview` — Preview a Plymouth boot screen with custom colors and logo
- `omarchy-plymouth-reset` — Restore the default Omarchy Plymouth boot theme and SDDM login screen
- `omarchy-plymouth-set` — Set the Plymouth boot theme colors and logo
- `omarchy-plymouth-set-by-theme` — Set the Plymouth boot theme from an Omarchy theme
- `omarchy-plymouth-switcher` — Open the Plymouth unlock screen switcher

### `power` (1)
- `omarchy-power-present` — Returns true if external power is connected.

### `powerprofiles` (3)
- `omarchy-powerprofiles-init` — Set the correct power profile on boot based on current AC/battery state.
- `omarchy-powerprofiles-list` — Returns a list of all the available power profiles on the system.
- `omarchy-powerprofiles-set` — Set and remember the power profile for AC or battery use

### `refresh` (11)
- `omarchy-refresh-applications` — Ensure default application launchers and mise wrappers are installed.
- `omarchy-refresh-chromium` — Refresh the ~/.config/chromium-flags.conf file from the Omarchy defaults.
- `omarchy-refresh-config` — Copy a shipped user config from $OMARCHY_PATH/config into ~/.config (backs up your version).
- `omarchy-refresh-hyprland` — Overwrite all the user Hyprland Lua configs in ~/.config/hypr with the Omarchy defaults.
- `omarchy-refresh-hyprsunset` — Overwrite the user config for hyprsunset with the Omarchy default and restart the service.
- `omarchy-refresh-limine` — Overwrite the user config for the Limine bootloader and rebuild it.
- `omarchy-refresh-pacman` — Overwrite the package configuration for /etc/pacman with the Omarchy default of using its dedicated mirrors and repositories, then update all packages.
- `omarchy-refresh-plymouth` — Overwrite the user config for the Plymouth drive decryption and boot sequence with the Omarchy default and rebuild it.
- `omarchy-refresh-sddm` — Refresh the SDDM theme from default
- `omarchy-refresh-shell` — Reset shell.json to Omarchy defaults
- `omarchy-refresh-tmux` — Overwrite the user tmux config with the Omarchy default and reload tmux.

### `reinstall` (2)
- `omarchy-reinstall-configs` — Reset Omarchy user configs and shipped defaults in $HOME (destructive)
- `omarchy-reinstall-pkgs` — Reinstall all default Omarchy packages from the stable channel

### `remove` (20)
- `omarchy-remove-browser` — Remove a supported browser and clean up Omarchy browser defaults
- `omarchy-remove-dev-env` — Remove a development environment that was previously installed via omarchy-install-dev-env.
- `omarchy-remove-gaming-battlenet` — Remove Battle.net, its Proton prefix, installed games, and desktop entry.
- `omarchy-remove-gaming-geforce-now` — Remove the GeForce NOW Flatpak app and its data.
- `omarchy-remove-gaming-heroic` — Remove Heroic Games Launcher and its game libraries, configs, and caches.
- `omarchy-remove-gaming-lutris` — Remove Lutris, Wine, umu-launcher, and all their configs and caches.
- `omarchy-remove-gaming-minecraft` — Remove the Minecraft launcher along with its worlds, mods, and caches.
- `omarchy-remove-gaming-retroarch` — Remove RetroArch, all libretro cores, and its config/saves. Leaves ~/Games/roms and ~/Games/bios alone.
- `omarchy-remove-gaming-steam` — Remove Steam and all of its game libraries, configs, and caches.
- `omarchy-remove-gaming-xbox-cloud` — Remove the Xbox Cloud Gaming web app.
- `omarchy-remove-gaming-xbox-controllers` — Remove the xpadneo Xbox controller driver and undo its module/blacklist config.
- `omarchy-remove-launcher-entry` — Remove or uninstall the selected launcher entry
- `omarchy-remove-preinstalls` — Remove preinstalled Omarchy applications (web apps, TUIs, and selected packages).
- `omarchy-remove-security-fido2` — Remove FIDO2 authentication from sudo and polkit
- `omarchy-remove-security-fingerprint` — Remove fingerprint authentication from sudo, polkit, and lock screen
- `omarchy-remove-security-sshd` — Disable the OpenSSH server, close the firewall port, and optionally remove authorized keys
- `omarchy-remove-service-1password` — Remove 1Password and its Chromium extension.
- `omarchy-remove-service-dropbox` — Remove Dropbox and its bar plugin.
- `omarchy-remove-service-sunshine` — Remove Sunshine and close Omarchy-managed Moonlight streaming ports.
- `omarchy-remove-service-tailscale` — Remove Tailscale and its bar plugin.

### `restart` (15)
- `omarchy-restart-app` — Restart an application by killing it and relaunching via uwsm.
- `omarchy-restart-audio` — Restart audio services and recover stuck USB audio devices.
- `omarchy-restart-bluetooth` — Unblock and restart the bluetooth service.
- `omarchy-restart-btop` — Reload btop configuration (used by the Omarchy theme switching).
- `omarchy-restart-gum` — Export the current theme's gum styling into the environment
- `omarchy-restart-helix` — Reload Helix configuration
- `omarchy-restart-hyprctl` — Reload hyprland configuration (used by the Omarchy theme switching).
- `omarchy-restart-hyprsunset` — Restart the hyprsunset service (used for blue light filtering/night light).
- `omarchy-restart-opencode` — Reload opencode configuration (used by the Omarchy theme switching).
- `omarchy-restart-shell` — Restart the Omarchy shell
- `omarchy-restart-terminal` — Reload supported terminal emulators after config changes
- `omarchy-restart-tmux` — Restart tmux if running with the latest configuration
- `omarchy-restart-trackpad` — Reset the trackpad by unbinding and rebinding its driver.
- `omarchy-restart-wifi` — Unblock and restart the Wi-Fi service.
- `omarchy-restart-xcompose` — Restart the XCompose input method service (fcitx5) to apply new compose key settings.

### `setup` (7)
- `omarchy-setup-direct-boot` — Add or remove an EFI boot entry for the Omarchy UKI, allowing the system to boot directly
- `omarchy-setup-hardware` — Apply Omarchy hardware-specific packages and system configuration
- `omarchy-setup-lock` — Configure Quickshell lock screen authentication
- `omarchy-setup-security-fido2` — Set up FIDO2 authentication for sudo and polkit
- `omarchy-setup-security-fingerprint` — Set up fingerprint authentication for sudo, polkit, and lock screen
- `omarchy-setup-security-sshd` — Set up the OpenSSH server, open the firewall, and authorize an SSH key
- `omarchy-setup-system` — Apply Omarchy system setup in the installed target

### `shell` (1)
- `omarchy-shell-config` — Shared helpers for editing ~/.config/omarchy/shell.json (source this, don't run it).

### `show` (2)
- `omarchy-show-done` — Display a "Done!" message with a spinner and wait for user to press any key.
- `omarchy-show-logo` — Display the Omarchy logo in the terminal using green color.

### `sudo` (3)
- `omarchy-sudo-keepalive` — Prompt for sudo once and keep the credential alive in the background.
- `omarchy-sudo-passwordless` — Toggle passwordless sudo for the current user.
- `omarchy-sudo-reset` — Reset the sudo lockout/faillock for the current user.

### `system` (9)
- `omarchy-system-lid-close` — Lock and reconcile displays when the laptop lid closes
- `omarchy-system-lock` — Lock the computer and turn off the display
- `omarchy-system-logout` — Log out after closing application windows
- `omarchy-system-reboot` — Reboot after closing application windows
- `omarchy-system-shutdown` — Shut down after closing application windows
- `omarchy-system-sleep-lock` — Lock before suspend and wait for the session lock to become secure
- `omarchy-system-sleep-monitor` — Monitor sleep preparation and lock before suspend
- `omarchy-system-stats` — Print CPU and memory stats for the shell
- `omarchy-system-wake` — Wake displays and restore brightness after idle

### `theme` (29)
- `omarchy-theme-bg-cache` — Cache background switcher thumbnails for the current theme
- `omarchy-theme-bg-current` — Show current background
- `omarchy-theme-bg-install` — Open the current theme's user background folder
- `omarchy-theme-bg-next` — Cycle to the next background for the current theme
- `omarchy-theme-bg-set` — Set the current background image
- `omarchy-theme-bg-switcher` — Open the Omarchy background switcher
- `omarchy-theme-color` — Resolve semantic colors from an Omarchy theme colors.toml
- `omarchy-theme-colors-from-alacritty` — Generate a theme's colors.toml from its alacritty.toml palette
- `omarchy-theme-current` — Show current theme
- `omarchy-theme-dir` — Print the directory holding a theme, preferring a user-installed copy
- `omarchy-theme-install` — Install a theme from a git repository
- `omarchy-theme-list` — List available themes
- `omarchy-theme-osc` — Print OSC sequences for an Omarchy color theme
- `omarchy-theme-refresh` — Refresh the current theme from its templates.
- `omarchy-theme-remove` — Remove a user-installed theme
- `omarchy-theme-set` — Apply an Omarchy theme
- `omarchy-theme-set-browser` — Apply the current theme color to Chromium, Chrome, Edge, and Brave
- `omarchy-theme-set-foot` — Apply current Omarchy theme colors to running Foot terminals
- `omarchy-theme-set-gnome` — Apply the current theme to GNOME color mode and icon settings
- `omarchy-theme-set-keyboard` — Apply the current theme keyboard color to supported keyboards
- `omarchy-theme-set-keyboard-asus-rog` — Apply the current theme keyboard color to ASUS ROG keyboards
- `omarchy-theme-set-keyboard-f16` — Apply the current theme keyboard color to Framework Laptop 16 keyboards
- `omarchy-theme-set-obsidian` — Sync Omarchy theme to all Obsidian vaults
- `omarchy-theme-set-pi` — Sync the generated Omarchy Pi theme
- `omarchy-theme-set-templates` — Generate themed config files from Omarchy templates
- `omarchy-theme-set-tmux` — Sync current Omarchy theme environment into tmux
- `omarchy-theme-set-vscode` — Sync Omarchy theme to VS Code, VSCodium, and Cursor
- `omarchy-theme-switcher` — Open the Omarchy theme switcher
- `omarchy-theme-update` — Update user-installed git themes

### `tmux` (1)
- `omarchy-tmux-alert` — Show or jump to tmux windows waiting for attention

### `toggle` (11)
- `omarchy-toggle-bar` — Toggle bar visibility without killing the Omarchy shell
- `omarchy-toggle-enabled` — Check if a toggle is enabled (flag file exists)
- `omarchy-toggle-hybrid-gpu` — Toggle dedicated vs integrated GPU mode via supergfxd (for hybrid gpu laptops, like Asus G14).
- `omarchy-toggle-idle` — Toggle idle behavior so the system either idles normally or stays awake
- `omarchy-toggle-input-device` — Enable, disable, or toggle a Hyprland input device
- `omarchy-toggle-nightlight` — Toggle nightlight screen temperature
- `omarchy-toggle-notification-silencing` — Toggle notification do-not-disturb mode
- `omarchy-toggle-screensaver` — Toggle screensaver availability
- `omarchy-toggle-suspend` — Toggle suspend availability in the system menu
- `omarchy-toggle-touchpad` — Enable, disable, or toggle the touchpad
- `omarchy-toggle-touchscreen` — Enable, disable, or toggle the touch functionality of the screen

### `transcode` (1)
- `omarchy-transcode-ascii` — Transcode an image into ASCII/Unicode art text

### `tui` (3)
- `omarchy-tui-install` — Create a desktop launcher for a terminal UI app
- `omarchy-tui-remove` — Remove a terminal UI desktop launcher
- `omarchy-tui-remove-all` — Remove all TUIs installed via omarchy-tui-install.

### `update` (15)
- `omarchy-update-analyze-logs` — Check the update log for known failure conditions
- `omarchy-update-aur-pkgs` — Update AUR packages if any are installed
- `omarchy-update-available` — Check whether Omarchy updates are available.
- `omarchy-update-confirm` — Prompt for confirmation before starting an update
- `omarchy-update-dev` — Update the active Omarchy dev checkout
- `omarchy-update-firmware` — Update system firmware using fwupd. Ensures the fwupd EFI binary is installed
- `omarchy-update-keyring` — Ensure the Omarchy and Arch keyring packages are installed and populated
- `omarchy-update-mise` — Update mise-managed tools
- `omarchy-update-orphan-pkgs` — Review and optionally remove orphaned system packages after updates
- `omarchy-update-pacman-guard` — Prevent direct pacman system upgrades from bypassing omarchy update.
- `omarchy-update-perform` — Compatibility wrapper for omarchy-update -y.
- `omarchy-update-restart` — Prompt for required reboot or service restarts after updates
- `omarchy-update-system-pkgs` — Update system packages with pacman
- `omarchy-update-time` — Restart system time synchronization
- `omarchy-update-user-notify` — Compatibility wrapper for omarchy-migrate-notify.

### `upgrade` (1)
- `omarchy-upgrade-to-quattro` — Upgrade a legacy Omarchy install to the package-backed Omarchy quattro layout.

### `upload` (1)
- `omarchy-upload-log` — Upload logs to logs.omarchy.org

### `version` (3)
- `omarchy-version-branch` — Print the active Omarchy dev-link git branch
- `omarchy-version-channel` — Print the active Omarchy mirror and package channel
- `omarchy-version-pkgs` — Print when system packages were last upgraded

### `voxtype` (5)
- `omarchy-voxtype-config` — Open Voxtype configuration
- `omarchy-voxtype-install` — Install and configure Voxtype dictation
- `omarchy-voxtype-model` — Open Voxtype AI model setup
- `omarchy-voxtype-remove` — Remove Voxtype dictation and its configuration
- `omarchy-voxtype-status` — Stream voxtype --follow status as bar-friendly JSON

### `weather` (3)
- `omarchy-weather-icon` — Returns a weather condition icon, adjusted for live sunrise and sunset.
- `omarchy-weather-location` — Show or set the location used for weather reports
- `omarchy-weather-status` — Returns a formatted weather status string with temperature and wind speed.

### `webapp` (5)
- `omarchy-webapp-handler-hey` — Open HEY webmail and translate mailto links
- `omarchy-webapp-handler-zoom` — Open Zoom web meetings from browser protocol links
- `omarchy-webapp-install` — Create a desktop launcher for a web app
- `omarchy-webapp-remove` — Remove a web app desktop launcher
- `omarchy-webapp-remove-all` — Remove all web apps installed via omarchy-webapp-install.

### `windows` (1)
- `omarchy-windows-vm` — Install, launch, stop, inspect, or remove the Windows VM

## 9. `shell/` — the Quickshell desktop (replaces waybar/walker/mako/swayosd/hyprlock/hypridle)

One long-running **Quickshell** (`quickshell-git`) instance, launched by Hyprland autostart, hosts the whole desktop UI; `omarchy-shell`/IPC is how CLIs talk to it. [^8^][^23^][^50^]

- `shell/shell.qml` — `ShellRoot` entry point; owns `PluginRegistry`, `BarWidgetRegistry`, `AppLibrary` singletons. [^50^]
- `shell/Commons/`, `shell/Ui/` — QML design system (Border, Color, Style primitives; ~30 widgets: Panel, Dropdown, Toggle, Slider, TextField, KeyboardPanel…). [^2^]
- `shell/services/` — `PluginRegistry.qml`, `BarWidgetRegistry.qml`, `AppLibrary.qml`. [^2^]
- **First-party plugins** (`shell/plugins/`, each with a `manifest.json`): [^2^][^8^]
  - `bar` — the top bar; widgets: ActiveWindow, Clock, Indicators, KeyboardLayout, Microphone, Spacer, SystemUpdate, Tray, Workspaces; indicators: Dictation, Dnd, NightLight, Reminder, ScreenRecording, StayAwake, TmuxAlert
  - `menu` — the Omarchy menu/launcher (SUPER+SPACE); `clipboard` (history); `emojis`; `image-picker`; `background` (wallpaper overlay); `lock` (lock screen); `notifications` (daemon + history); `osd` (volume/brightness OSD); `reminders`; `polkit` (auth agent); `model-usage` (AI model usage meter); `dev-gallery`
  - `panels/` — settings panels: audio, bluetooth, dropbox, monitor, network, power, tailscale, weather
  - `services/` — headless: battery, idle, media (MPRIS), nightlight, tmux
- **Plugin kinds**: `bar-widget`, `bar` (full replacement), `panel`, `overlay`, `menu`, `service`. Third-party plugins are git repos cloned to `~/.config/omarchy/plugins/<id>/` via `omarchy plugin add`, land disabled, unsandboxed. IPC methods: `ping/summon/hide/toggle/call/rescanPlugins/reloadConfig/setPluginEnabled/listPlugins`. [^8^]
- **Config**: `~/.config/omarchy/shell.json` — default: idle screensaver 150s / lock 300s; bar top, opaque, center-anchored on clock; layout left = menu + workspaces, center = indicators/clock… [^48^]

## 10. `migrations/` — version history

41 timestamped shell scripts (`migrations/<unix-ts>.sh`), run per-user by `omarchy-migrate`, idempotent, state in `~/.local/state/omarchy/migrations/`; pending-check only at login (per the newest migration). They reveal the recent evolution [^38^][^7^]:

| Migration | Message (first line, verbatim) |
|---|---|
| 1778623107 | Install MPRIS support for mpv |
| 1780057136 | Make Shift+Enter distinguishable for terminals and Codex |
| 1780294774 | Remove leading zero from bar clock date |
| 1780517689 | Add yt-dlp download extension (Alt+Shift+D) to Chromium-based browsers |
| 1780739888 | Use dua for Disk Usage TUI |
| 1781043107 | Move current Omarchy theme state to ~/.local/state |
| 1781063758 | Update Hyprland Lua entrypoint to load Omarchy bootstrap |
| 1781158082 | Relink Neovim theme to Omarchy current state |
| 1781286586 | Replace Satty with Tensaku |
| 1781485962 | Move stock Hyprland user overrides into package defaults |
| 1781587663 | Enable secure remote Neovim clipboard support |
| 1781793381 | Auto-mount removable drives by default with udiskie |
| 1781984677 | Normalize Snapper snapshot services |
| 1782002156 | Retire systemd-networkd in favor of NetworkManager |
| 1782049344 | Disable Limine Snapper warning notifier |
| 1784401744 | Backfill hardware support and tmux settings added before Omarchy quattro |
| 1784476564 | Keep non-Latin keyboard layouts out of the initramfs so the LUKS passphrase stays typeable |
| 1784479832 | Enable Kitty cwd lookup through a remote control socket |
| 1784508556 | Pin browser password store to gnome-libsecret (prevents cookie/login loss on Hyprland) |
| 1784510887 | Switch Brave Origin from the beta to the stable release |
| 1784521870 | Stop the migration notifier from re-triggering itself in a loop |
| 1784568652 | Stop waiting for the network before showing the desktop |
| 1784672586 | Switch to the Omarchy quickshell-git build so shell restarts wait for instance exit |
| 1784763917 | Install the native messaging host for the Chromium Copy URL extension |
| 1784767406 | Remove the obsolete Voxtype Hyprland toggle |
| 1784818437 | Gate sudo and polkit fingerprint auth behind the lid state (password when the lid is shut) |
| 1784849592 | Add tmux hooks that surface waiting windows in the bar |
| 1784909971 | Regenerate mise wrappers to stop them recursing through PATH |
| 1784914435 | Keep Wi-Fi power save off for lower latency |
| 1784917531 | Unpack the initramfs synchronously so Plymouth survives early boot |
| 1784955584 | Track tmux output while its terminal is unfocused |
| 1784960000 | Install the speaker tuning for XPS 2026 14/16 |
| 1784961000 | Tune reclaim for swap on zram |
| 1784970000 | Give the pre-suspend lock a window it can actually finish in |
| 1784989000 | Move the bar indicators to the left of the clock |
| 1785002349 | Repair Neovim theme symlinks the earlier relink missed |
| 1785013000 | Move zram tuning to a vendor drop-in |
| 1785090473 | Switch fingerprint support back to stock libfprint |
| 1785094500 | Resize zram to match the shipped config |
| 1785095882 | Only check for pending migrations at login, not on every package update |

Note the gap between `1782049344` and `1784401744` — the "backfill … before Omarchy quattro" migration marks the v3→v4 boundary inside the migration timeline. `bin/omarchy-upgrade-to-quattro` handles the release-channel switch for existing installs. [^38^][^2^]

## 11. Gaps / could not access

- **PKGBUILDs / ISO builder** live in the separate `omarchy-pkgs` repository (referenced by `docs/file-layout.md` and package-list comments); not analyzed here. No archinstall profile exists in this repo. [^7^][^31^]
- `config/foot/foot.ini`, `config/btop/btop.conf` and the remaining small configs were eventually fetched; `config/lazygit/config.yml`, `config/imv/config`, `config/fcitx5/conf/*`, `config/opencode/opencode.json`, `config/obsidian/user-flags.conf`, `config/hyprland-preview-share-picker/config.yaml`, `config/wireplumber/**`, `config/xournalpp/settings.xml`, `config/chromium/Default/Preferences` were listed but not quoted in full (presence + role recorded only).
- Per-theme `hyprland.lua` overrides (kanagawa, last-horizon, lumon, retro-82, solitude), `neovim.lua`, `vscode.json`, `btop.theme`, `chromium.theme`, `keyboard.rgb` files were not individually extracted — palettes above come from `colors.toml`, which templates render from.
- `docs/theming.md`, `docs/migrations.md`, `docs/update-process.md`, `docs/AUDIO-TUNING.md` were fetched but only summarized where used.
- Binary assets (wallpapers, PNGs, `default/fonts/omarchy/omarchy.ttf`) not analyzed.
- The `v3.8.4` (stable) tree differs from HEAD; this brief describes **HEAD = `quattro` branch** unless a tag is cited.

## Sources

[^1^]: https://api.github.com/repos/basecamp/omarchy
[^2^]: https://api.github.com/repos/basecamp/omarchy/git/trees/HEAD?recursive=1
[^3^]: https://api.github.com/repos/basecamp/omarchy/tags
[^4^]: https://api.github.com/repos/basecamp/omarchy/releases
[^5^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/version
[^6^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/README.md
[^7^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/docs/file-layout.md
[^8^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/docs/omarchy-shell.md
[^9^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/AGENTS.md
[^10^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/hyprland.lua
[^11^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/bindings.lua
[^12^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/looknfeel.lua
[^13^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/input.lua
[^14^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/monitors.lua
[^15^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/autostart.lua
[^16^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/hyprsunset.conf
[^17^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/hypr/xdph.conf
[^18^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/omarchy.lua
[^19^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/looknfeel.lua
[^20^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/input.lua
[^21^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/envs.lua
[^22^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/windows.lua
[^23^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/autostart.lua
[^24^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/bindings/tiling.lua
[^25^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/bindings/applications.lua
[^26^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/bindings/utilities.lua
[^27^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/bindings/media.lua
[^28^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/bindings/clipboard.lua
[^29^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/bindings/voxtype.lua
[^30^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/apps/terminals.lua
[^31^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/omarchy-base.packages
[^32^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/omarchy-other.packages
[^33^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/config/all.sh
[^34^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/hardware/all.sh
[^35^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/login/all.sh · https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/post-install/all.sh · https://raw.githubusercontent.com/basecamp/omarchy/HEAD/install/user/all.sh
[^36^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/themes/tokyo-night/colors.toml (+ sibling `themes/<name>/colors.toml` files for catppuccin, gruvbox, nord, everforest, osaka-jade, ristretto)
[^37^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/bin/omarchy
[^38^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/migrations/ (e.g. /migrations/1785095882.sh)
[^39^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/alacritty/alacritty.toml
[^40^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/ghostty/config
[^41^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/kitty/kitty.conf
[^42^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/foot/foot.ini
[^43^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/starship.toml
[^44^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/tmux/tmux.conf
[^45^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/btop/btop.conf
[^46^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/chromium-flags.conf
[^47^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/git/config
[^48^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/config/omarchy/shell.json
[^49^]: https://github.com/basecamp/omarchy/tree/HEAD/default/themed
[^50^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/shell/shell.qml
[^51^]: https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/hypr/apps.lua
[^52^]: https://api.github.com/repos/basecamp/omarchy/commits
