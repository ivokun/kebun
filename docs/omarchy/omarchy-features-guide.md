# Omarchy: Complete Features Guide

> A thorough reference for every feature, subsystem, and design pattern in the Omarchy Linux desktop environment.

---

## Table of Contents

1. [Desktop Shell](#1-desktop-shell)
2. [Window Management](#2-window-management)
3. [Theme System](#3-theme-system)
4. [Terminal Experience](#4-terminal-experience)
5. [Unified Clipboard](#5-unified-clipboard)
6. [Notifications](#6-notifications)
7. [Screenshots & Captures](#7-screenshots--captures)
8. [Audio System](#8-audio-system)
9. [Lock Screen & Idle](#9-lock-screen--idle)
10. [System Menu](#10-system-menu)
11. [Keybindings](#11-keybindings)
12. [Utility Commands](#12-utility-commands)
13. [Application Launchers](#13-application-launchers)
14. [Floating TUI Pattern](#14-floating-tui-pattern)
15. [Development Environment](#15-development-environment)
16. [File Management](#16-file-management)
17. [Power Management](#17-power-management)
18. [Updates & Migrations](#18-updates--migrations)
19. [AI Integration](#19-ai-integration)
20. [System Integration](#20-system-integration)

---

## 1. Desktop Shell

### 1.1 Hyprland Compositor

Omarchy is built on **Hyprland**, a dynamic tiling Wayland compositor. Omarchy configures it with a multi-layer config system:

**Layer order (later wins):**
```
default/hypr/autostart.conf       # Autostart apps
default/hypr/bindings/*.conf      # All keybindings
default/hypr/envs.conf            # Environment variables
default/hypr/looknfeel.conf       # Animations, decoration
default/hypr/input.conf           # Keyboard, touchpad
default/hypr/windows.conf         # Window rules
default/hypr/apps.conf            # App-specific rules
~/.config/omarchy/current/theme/  # Theme colors
~/.config/hypr/*.conf             # User overrides
~/.local/state/omarchy/toggles/   # Runtime toggles
```

**Key settings:**
- **Layout**: Dwindle (spiral) by default, toggleable to Master
- **Gaps**: 5px inner, 10px outer
- **Borders**: 2px, themed active/inactive colors
- **Animations**: Custom bezier curves (easeOutQuint for windows, quick for fades)
- **Decoration**: Rounding 0 (sharp corners), blur 2 passes, shadows
- **Transparency**: 0.97 opacity by default, 1.0 for media apps
- **XWayland**: force_zero_scaling for crisp HiDPI
- **Background**: Solid color from theme (no wallpaper by default)

### 1.2 Waybar Status Bar

Waybar sits at the top (26px height) with three zones:

**Left modules:**
- `custom/omarchy` — Logo icon, opens main menu on click
- `hyprland/workspaces` — Workspace buttons 1-0 with icons

**Center modules:**
- `clock` — Day + time (e.g. "Monday 14:30")
- `custom/weather` — Live weather from Open-Meteo
- `custom/update` — Update availability indicator
- `custom/voxtype` — Dictation status icon
- `custom/screenrecording-indicator` — Recording state
- `custom/idle-indicator` — Idle lock toggle state
- `custom/notification-silencing-indicator` — DND state

**Right modules:**
- `group/tray-expander` — Collapsible system tray
- `bluetooth` — Bluetooth icon + device count
- `network` — WiFi signal strength / Ethernet
- `pulseaudio` — Volume icon + tooltip
- `cpu` — CPU icon, opens btop on click
- `battery` — Capacity + charging state

**Module interactions:**
| Module | Click | Right-click |
|---|---|---|
| `custom/omarchy` | `omarchy-menu` | Terminal |
| `cpu` | `omarchy-launch-or-focus-tui btop` | Alacritty |
| `clock` | Nothing | Timezone selector |
| `network` | `omarchy-launch-wifi` | — |
| `pulseaudio` | `omarchy-launch-audio` | `pamixer -t` |
| `battery` | `omarchy-menu power` | Battery status notify |
| `bluetooth` | `omarchy-launch-bluetooth` | — |

### 1.3 Walker Application Launcher

Walker replaces wofi/rofi as the primary launcher. It's configured with:
- **App launcher mode**: `Super+Space` — fuzzy-find and launch applications
- **Clipboard manager**: `Super+Ctrl+V` — browse clipboard history (via cliphist)
- **Emoji picker**: `Super+Ctrl+E` — search and insert emojis
- **Dmenu mode**: Used internally by scripts for selection menus
- **Symbol mode**: `Super+Ctrl+E` for special characters

Walker is styled to match the active theme with consistent colors and fonts.

### 1.4 Mako Notifications

Mako is the notification daemon with:
- **Position**: Top-right
- **Size**: 420px wide, 20px outer margin
- **Timeout**: 5000ms default, 0 for critical
- **Do Not Disturb mode**: Invisible notifications, toggleable
- **Style**: Themed border, background, text colors
- **Actions**: Dismiss, invoke, restore via keybindings

---

## 2. Window Management

### 2.1 Tiling Layouts

Omarchy uses **two layouts** toggleable with `Super+L`:

**Dwindle** (default): Spiral/binary splitting. Windows divide recursively. Settings:
- `preserve_split = true` — remembers split direction
- `force_split = 2` — forces split direction (2 = automatic)

**Master**: Traditional master/stack layout. Settings:
- `new_status = "master"` — new windows become master

### 2.2 Window States

| State | Keybinding | Description |
|---|---|---|
| Tiled | Default | Participates in layout |
| Floating | `Super+T` | Free-floating, can resize freely |
| Fullscreen | `Super+F` | True fullscreen (0) |
| Tiled fullscreen | `Super+Ctrl+F` | Fills layout area (state 0 2) |
| Full width | `Super+Alt+F` | Horizontal maximize (1) |
| Pseudo | `Super+P` | Dwindle pseudo-tiling |
| Popped | `Super+O` | Float + pin + center (Picture-in-Picture) |
| Grouped | `Super+G` | Tabbed/stacked group |

### 2.3 Window Rules (Dynamic Tagging)

Omarchy uses **Hyprland's tagging system** (0.53+) for flexible window rules:

**The default-opacity tag:**
```hyprlang
windowrule = tag +default-opacity, match:class .*        # Tag all windows
windowrule = opacity 0.97 0.9, match:tag default-opacity  # Apply opacity
```

**App-specific tags:**
```hyprlang
tag +floating-window — for TUIs (wiremix, btop, bluetui)
tag +chromium-based-browser — Chrome/Brave/Edge/Vivaldi
tag +firefox-based-browser — Firefox/Zen/LibreWolf
tag +terminal — Alacritty/kitty/Ghostty/foot
tag +pop — Popped windows (rounded corners)
```

**Special rules:**
- Media apps (zoom, vlc, mpv): opacity 1.0 1.0 (no transparency)
- Floating windows: float + center + size 875x600
- Idle inhibit: fullscreen windows and `+noidle` tag
- Bitwarden: no screen share, floating
- Calculator: floating

### 2.4 Workspace System

- **10 workspaces**: `Super+[1-0]` to switch
- **Named scratchpad**: `Super+S` toggles special workspace
- **Workspace cycling**: `Super+Tab` next, `Super+Shift+Tab` previous, `Super+Ctrl+Tab` former
- **Move to workspace**: `Super+Shift+[1-0]` (with follow), `Super+Shift+Alt+[1-0]` (silent)
- **Move workspace to monitor**: `Super+Shift+Alt+Arrow`
- **Mouse scrolling**: `Super+scroll` cycles workspaces

### 2.5 Window Groups

Groups are like browser tabs for application windows:
- `Super+G` — Toggle grouping (group/ungroup active window)
- `Super+Alt+Arrow` — Move window into adjacent group
- `Super+Alt+G` — Move out of group
- `Super+Alt+Tab` — Cycle within group
- `Super+Alt+[1-5]` — Switch to group window by number
- `Super+Alt+scroll` — Scroll through grouped windows

### 2.6 Resize System

Omarchy provides **granular resize controls** using the `-` and `=` keys:

| Keybinding | Amount |
|---|---|
| `Super + -/=` | 100px (normal) |
| `Super + Shift + -/=` | Vertical only |
| `Super + Alt + -/=` | 25px (fine) |
| `Super + Ctrl + -/=` | 300px (coarse) |

Plus `Super+Shift+Arrow` for swapping windows and `Super+mouse drag` for manual resize.

---

## 3. Theme System

### 3.1 20 Built-in Themes

| Theme | Style | Palette |
|---|---|---|
| catppuccin | Soft pastel dark | Mauve/Blue/Pink |
| catppuccin-latte | Soft pastel light | Same, light |
| ethereal | Minimal clean | Gray/Teal |
| everforest | Nature green/brown | Green/Beige |
| flexoki-light | Reading-friendly | Warm gray/Red |
| gruvbox | Classic retro retro | Brown/Orange |
| hackerman | Matrix green | Green/Black |
| kanagawa | Japanese-inspired | Blue/Gold |
| lumon | Severance TV show | Blue/Cold |
| matte-black | OLED pure black | Black/White |
| miasma | Dark purple haze | Purple/Green |
| nord | Arctic blue | Blue/Cyan |
| osaka-jade | Jade green | Green/White |
| retro-82 | 1980s aesthetic | Neon/Magenta |
| ristretto | Dark warm brown (default) | Brown/Teal |
| rose-pine | Rosé pine pink | Pink/Pine |
| rose-pine-dawn | Light variant | Same, light |
| tokyo-night | Dark blue/purple | Blue/Purple |
| vantablack | Ultra-black OLED | Near-black |
| white | Clean white | White/Gray |

### 3.2 Theme Application Scope

Each theme coordinates colors across **all components**:

- **Desktop**: Hyprland background, border colors, groupbar
- **Lock screen**: Hyprlock background, input field colors
- **Status bar**: Waybar CSS (background, text, module colors)
- **Notifications**: Mako (background, border, text)
- **Terminals**: Alacritty, Kitty, Ghostty, Foot color schemes
- **Launcher**: Walker theme
- **OSD**: SwayOSD style
- **System monitor**: Btop theme file
- **Editors**: Neovim, Helix color schemes
- **Git TUI**: Lazygit theme settings

### 3.3 Theme Switching

`omarchy-theme-set <theme-name>` atomically:
1. Copies theme files to `~/.config/omarchy/current/`
2. Symlinks theme configs into each app's config directory
3. Refreshes all running applications
4. Updates Hyprland colors via `hyprctl`
5. Restarts Waybar, Mako, Walker

---

## 4. Terminal Experience

### 4.1 Terminal Emulators

Omarchy supports **4 terminal emulators**, switchable via `omarchy-default-terminal`:

| Terminal | Class | Best For |
|---|---|---|
| **Alacritty** (default) | `Alacritty` | Speed, GPU-accelerated |
| **Kitty** | `kitty` | Graphics, kittens |
| **Ghostty** | `com.mitchellh.ghostty` | macOS-like experience |
| **Foot** | `org.codeberg.dnkl.foot` | Wayland-native, minimal |

All terminals share:
- Rose Pine Dawn (or active theme) color scheme
- CaskaydiaMono Nerd Font
- 97% opacity (matched to other windows)

### 4.2 Tmux

- **Plugin manager**: TPM (Tmux Plugin Manager)
- **Plugins**: sensible, resurrect, continuum
- **Theme**: Status bar themed to match active theme
- **Integration**: Sessions persist across terminal restarts

### 4.3 Shell (Bash + Starship)

- **Shell**: Bash 5 with custom configuration
- **Prompt**: Starship with theme-colored palette
- **Key features**: Atuin (history sync), zoxide (smart cd), direnv (env auto-load)

### 4.4 Terminal-CWD Detection

`omarchy-cmd-terminal-cwd` detects the working directory of the focused terminal window, enabling:
- `Super+Return` opens a new terminal in the same directory
- `Super+Alt+Shift+F` opens the file manager at the current directory

---

## 5. Unified Clipboard

Omarchy provides **system-wide clipboard shortcuts** that work everywhere:

| Keybinding | Action |
|---|---|
| `Super + C` | Copy (sends Ctrl+Insert internally) |
| `Super + V` | Paste (sends Shift+Insert internally) |
| `Super + X` | Cut (sends Ctrl+X internally) |
| `Super + Ctrl + V` | Clipboard history (walker + cliphist) |

This means you can use `Super+C/V` in **any application** — GTK, Qt, terminal, browser — and it just works. The `sendshortcut` dispatcher sends the actual Ctrl+C/V/X to the application, so it works with all native copy/paste mechanisms.

**Clipboard history** is managed by `cliphist` and browsed through Walker's clipboard module.

---

## 6. Notifications

### 6.1 Mako Configuration

- **Position**: Top-right corner
- **Default timeout**: 5000ms
- **Critical notifications**: Never timeout, shown on overlay layer
- **DND mode**: Invisible notifications (mode toggle)
- **Colors**: Themed border, background, text
- **Max icon size**: 32px

### 6.2 Notification Actions

| Keybinding | Action |
|---|---|
| `Super + ,` | Dismiss last notification |
| `Super + Shift + ,` | Dismiss all notifications |
| `Super + Ctrl + ,` | Toggle Do Not Disturb |
| `Super + Alt + ,` | Invoke action of last notification |
| `Super + Shift + Alt + ,` | Restore last dismissed notification |

### 6.3 Notification Indicators

Waybar shows a DND indicator in the center area when notification silencing is active.

---

## 7. Screenshots & Captures

### 7.1 Screenshot

| Keybinding | Action |
|---|---|
| `Print` | Region screenshot → open in swappy (editor) |
| `Shift + Print` | Region screenshot → clipboard |
| `Super + Print` | Color picker (hyprpicker) |
| `Super + Ctrl + Print` | OCR — extract text from screenshot |
| `Alt + Print` | Screen recording menu |

**Screenshot workflow:**
1. `grim -g "$(slurp)"` captures selected region
2. Pipe to `swappy -f -` for annotation/editing
3. Or pipe to `wl-copy` for direct clipboard

**OCR workflow:**
1. Capture region with grim+slurp
2. Pipe through `tesseract stdout`
3. Copy extracted text to clipboard via wl-copy

### 7.2 Screen Recording

`omarchy-capture-screenrecording` uses `wf-recorder` or similar:
- Select region with slurp
- Record to file
- Indicator appears in Waybar while recording
- Click indicator to stop

---

## 8. Audio System

### 8.1 Audio Stack

- **PipeWire**: Audio server
- **WirePlumber**: Session/policy manager
- **WireMix**: TUI audio mixer (launched from Waybar)
- **pamixer**: CLI volume control
- **playerctl**: Media playback control

### 8.2 Volume Controls

| Keybinding | Action |
|---|---|
| `XF86AudioRaiseVolume` | Volume up (+5%) |
| `XF86AudioLowerVolume` | Volume down (-5%) |
| `Alt + XF86AudioRaiseVolume` | Volume up precise (+1%) |
| `Alt + XF86AudioLowerVolume` | Volume down precise (-1%) |
| `XF86AudioMute` | Mute toggle |
| `XF86AudioMicMute` | Microphone mute toggle |
| `Super + XF86AudioMute` | Switch audio output device |

### 8.3 Media Playback

| Keybinding | Action |
|---|---|
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86AudioPlay/Pause` | Play/pause |

### 8.4 Audio TUI (WireMix)

Click the volume icon in Waybar → launches WireMix as a floating TUI:
- Shows all audio sinks, sources, streams
- Adjust volumes with keyboard
- Route streams between devices

### 8.5 Bluetooth Audio

`omarchy-launch-bluetooth` opens `bluetui` (floating TUI) for:
- Pair/connect Bluetooth devices
- Manage audio profiles (A2DP/HFP)
- Show battery levels of connected devices

---

## 9. Lock Screen & Idle

### 9.1 Hyprlock

The lock screen is themed to match the active theme:
- **Background**: Solid theme color with blur
- **Input field**: Centered password field with themed colors
- **Font**: CaskaydiaMono Nerd Font
- **Animations**: Disabled for instant response
- **Fingerprint**: Optional (if hardware supports it)

### 9.2 Hypridle (Idle Management)

Three listeners with cascading timeouts:

| Timeout | Action |
|---|---|
| 600s (10min) | Lock session |
| 605s (10min + 5s) | DPMS off (screen off) |
| 900s (15min) | Suspend to RAM |

**On resume**: DPMS on + restore brightness

### 9.3 Idle Toggle

`Super+Ctrl+I` toggles the idle daemon — useful when presenting or watching movies:
- On → normal idle behavior (lock after 10min)
- Off → never lock, never suspend

### 9.4 Lock Keybinding

`Super+Ctrl+L` locks immediately via `omarchy-system-lock`.

---

## 10. System Menu

### 10.1 Main Menu (`omarchy-menu`)

The primary system menu is a **Walker dmenu** with multiple submenus:

**`Super+Alt+Space`** or **`Super+Escape`** opens:
- **System submenu**: Lock, logout, reboot, shutdown
- **Capture submenu**: Screenshot, screen recording options
- **Toggle submenu**: Transparency, gaps, nightlight, idle, DND, waybar
- **Hardware submenu**: Monitor scaling, internal display, touchpad
- **Theme submenu**: Background picker, theme selector
- **Background submenu**: Browse and set wallpapers
- **Share submenu**: LocalSend file sharing
- **Reminder submenu**: Set/show/clear reminders

**`Super+Space`** — App launcher (Walker)
**`Super+Ctrl+Space`** — Background menu
**`Super+Shift+Ctrl+Space`** — Theme menu
**`Super+K`** — Keybindings help

### 10.2 Menu Architecture

`omarchy-menu` is a ~845 line script that:
1. Detects which submenu to show
2. Builds a list of options with descriptions
3. Pipes to Walker in dmenu mode
4. Executes the selected command

Submenus are called with: `omarchy-menu <submenu-name>` (e.g., `omarchy-menu capture`, `omarchy-menu toggle`)

---

## 11. Keybindings

### 11.1 Modifier Philosophy

| Modifier | Purpose |
|---|---|
| `Super` | Primary action |
| `Super + Shift` | Alternate/extended action |
| `Super + Ctrl` | System controls |
| `Super + Alt` | Extra/niche actions |
| `Super + Shift + Ctrl` | Configuration/layout changes |
| `Alt` | Cycling/navigation |

### 11.2 Binding Files

Keybindings are organized into 5 files:

```
default/hypr/bindings/
├── clipboard.conf       — Copy/paste/clipboard
├── media.conf           — Volume, brightness, media keys
├── tiling-v2.conf       — Window management, workspaces
├── utilities.conf       — Menus, toggles, captures
└── plain-bindings.conf  — App launchers
```

### 11.3 Descriptive Bindings (`bindd`)

Every binding uses Hyprland's `bindd` (descriptive binding) syntax:
```hyprlang
bindd = SUPER, W, Close window, killactive,
#         ^      ^       ^          ^
#    modifier   key  description  dispatcher
```

The description is what appears in `Super+K` keybindings help.

### 11.4 Complete Binding Reference

See the keybinding analysis in the previous response for the full list.

---

## 12. Utility Commands

### 12.1 Command Categories

Omarchy provides **234 shell commands** via `bin/omarchy-*`:

| Prefix | Count | Examples |
|---|---|---|
| `omarchy-ac-*` | 1 | AC power detection |
| `omarchy-audio-*` | 2 | Input mute, output switch |
| `omarchy-battery-*` | 6 | Present, capacity, remaining, monitor |
| `omarchy-brightness-*` | 4 | Display, keyboard, Apple display |
| `omarchy-capture-*` | 4 | Screenshot, recording, OCR |
| `omarchy-hw-*` | 14 | Hardware detection (ASUS, Dell, Framework, Surface...) |
| `omarchy-hyprland-*` | 15 | Window gaps, transparency, pop, layout, monitor |
| `omarchy-install-*` | 20 | Browsers, dev-env, gaming, VPNs |
| `omarchy-launch-*` | 10 | TUI, focus, browser, editor, webapp |
| `omarchy-pkg-*` | 7 | Add, remove, AUR helpers |
| `omarchy-powerprofiles-*` | 3 | List, set, init |
| `omarchy-refresh-*` | 20 | Reset any config to defaults |
| `omarchy-restart-*` | 25 | Restart any component |
| `omarchy-theme-*` | 12 | Set, list, install, remove themes |
| `omarchy-toggle-*` | 8 | Idle, nightlight, DND, touchpad, waybar |
| `omarchy-update-*` | 12 | Full update pipeline |

### 12.2 The CLI Router

`bin/omarchy` is a smart router that auto-discovers all subcommands from metadata comments in each script:

```bash
# omarchy:summary=Show battery capacity percentage
# omarchy:group=battery
```

Running `omarchy` without arguments shows all commands organized by group with descriptions.

---

## 13. Application Launchers

### 13.1 Launch-or-Focus Pattern

The core pattern for launching applications:

```
omarchy-launch-or-focus <window-pattern> <launch-command>
```

1. Check if a window matching `<window-pattern>` already exists
2. If yes → focus it (no duplicate)
3. If no → launch with `<launch-command>`

### 13.2 Launch Wrappers

| Script | Purpose |
|---|---|
| `omarchy-launch-browser` | Launch/focus browser ( Chromium ) |
| `omarchy-launch-editor` | Launch/focus editor ( Neovim ) |
| `omarchy-launch-tui` | Launch TUI in terminal with app-id |
| `omarchy-launch-or-focus-tui` | TUI with focus-or-launch + app-id |
| `omarchy-launch-audio` | Launch WireMix (floating TUI) |
| `omarchy-launch-bluetooth` | Launch Bluetui (floating TUI) |
| `omarchy-launch-wifi` | Launch Impala (floating TUI) |
| `omarchy-launch-walker` | Launch Walker with module |
| `omarchy-launch-webapp` | Launch a web app in its own window |

### 13.3 Web Apps

Omarchy can install websites as "apps" with their own window class:
```bash
omarchy-webapp-install "https://chatgpt.com"   # Creates .desktop entry
omarchy-webapp-handler-hey                      # Hey email client
omarchy-webapp-handler-zoom                     # Zoom web client
```

Web apps get:
- Dedicated window class for Hyprland rules
- Own .desktop file in applications/
- Copy-URL extension support (Shift+Alt+L copies current URL)

---

## 14. Floating TUI Pattern

### 14.1 The Pattern

TUIs launched from Waybar use a consistent pattern:

1. **Set app-id**: `org.omarchy.<appname>` (e.g., `org.omarchy.wiremix`)
2. **Launch via xdg-terminal-exec**: Respects default terminal setting
3. **Hyprland matches on class**: Floats, centers, sizes to 875x600
4. **Focus-or-launch**: Click again → focus existing window

### 14.2 Floating Window Rules

```hyprlang
# Tag all org.omarchy.* apps as floating
tag +floating-window, match:class (org.omarchy.bluetui|org.omarchy.impala|org.omarchy.wiremix|org.omarchy.btop|...)

# Apply floating properties
float on,   match:tag floating-window
center on,  match:tag floating-window
size 875 600, match:tag floating-window
```

### 14.3 Floating TUI Apps

| App | Launched From | Purpose |
|---|---|---|
| WireMix | Volume icon | Audio mixer |
| Bluetui | Bluetooth icon | Bluetooth management |
| Impala | Network icon | WiFi management |
| btop | CPU icon | System monitor |
| foot (general) | Various | Generic terminal TUIs |

---

## 15. Development Environment

### 15.1 Editor: Neovim

- Full configuration in `config/nvim/`
- Theme syncs with active Omarchy theme
- Lazy.nvim for plugin management
- LSP, treesitter, telescope configured

### 15.2 Git Integration

| Tool | Purpose |
|---|---|
| `git` | With delta pager, aliases |
| `lazygit` | TUI git client with themed UI |
| `gpg` | Signing commits |

### 15.3 Dev Environment Setup

`omarchy-install-dev-env` installs:
- mise (language version manager)
- Docker with socket activation
- Development databases

### 15.4 Terminal Workflow Tools

| Tool | Purpose |
|---|---|
| `atuin` | Shell history sync/search |
| `zoxide` | Smart cd (learns your directories) |
| `direnv` | Per-directory environment variables |
| `fzf` | Fuzzy finder |
| `tmux` | Terminal multiplexer with session persistence |

---

## 16. File Management

### 16.1 Nautilus (GNOME Files)

- Default file manager
- Launched with `Super+Shift+F`
- Opens with `--new-window` flag
- Can open at terminal CWD: `Super+Alt+Shift+F`

### 16.2 File Sharing

`Super+Ctrl+S` opens the share menu using **LocalSend** for cross-device file transfer.

### 16.3 MIME Types

Default applications are configured via `mimetypes.sh` during installation:
- Text files → Neovim
- HTML → Chromium
- HTTP/HTTPS → Chromium
- Mailto → Chromium

---

## 17. Power Management

### 17.1 Power Profiles

`powerprofilesctl` manages three profiles:
- **power-saver**: Extended battery life
- **balanced**: Default
- **performance**: Maximum performance

Toggle with `omarchy-menu power` or Waybar module.

### 17.2 Battery Monitoring

Commands available:
- `omarchy-battery-present` — Check if battery exists
- `omarchy-battery-capacity` — Current percentage
- `omarchy-battery-remaining` — Percentage with icon
- `omarchy-battery-remaining-time` — Estimated time
- `omarchy-battery-status` — Full status string
- `omarchy-battery-monitor` — Background monitor daemon

### 17.3 Hibernation

`omarchy-hibernation-setup` configures:
- Swap file/partition
- Resume kernel parameter
- Initramfs hooks

Remove with `omarchy-hibernation-remove`.

### 17.4 Lid Switch

- **Lid close** with external monitors → disable internal display
- **Lid open** → re-enable internal display
- Both are automatic via `bindl` (device binds)

---

## 18. Updates & Migrations

### 18.1 Update System

`omarchy-update` performs:
1. `git pull` the omarchy repo
2. Run pending migration scripts
3. Update system packages (pacman)
4. Update AUR packages (if any)
5. Restart affected services

Variants:
- `omarchy-update-without-idle` — Update without idle timer
- `omarchy-update-firmware` — Include firmware updates
- `omarchy-update-analyze-logs` — Analyze update logs

### 18.2 Migration System

When Omarchy updates, numbered migration scripts run automatically:

```
migrations/
  001-initial-setup.sh
  002-add-swayosd.sh
  003-fix-permissions.sh
  ...
```

Each migration is idempotent and only runs once. This allows Omarchy to:
- Add new packages
- Change config formats
- Fix permissions
- Migrate user settings

### 18.3 Version Tracking

- `version` file in repo root tracks current version
- `omarchy-version` shows current version, branch, channel
- `omarchy-update-available` checks if update is available

---

## 19. AI Integration

### 19.1 Voxtype (Voice Dictation)

**Keybindings:**
| Keybinding | Action |
|---|---|
| `Super+Ctrl+X` | Toggle dictation |
| `F9` (hold) | Push-to-talk dictation |

**Commands:**
- `omarchy-voxtype-status` — Show dictation state
- `omarchy-voxtype-config` — Configure settings
- `omarchy-voxtype-model` — Select whisper model
- `omarchy-voxtype-install/remove` — Install/remove

**Waybar indicator**: Shows recording/transcribing state in center modules.

### 19.2 Pi AI Agent

Omarchy integrates with the Pi AI agent (OpenCode):
- `omarchy-ai-skill.sh` — Setup integration
- Dark/light mode syncs with Omarchy theme
- Accessible via `omarchy-menu` or dedicated keybinding

---

## 20. System Integration

### 20.1 Plymouth Boot Splash

- Omarchy-branded boot animation
- `omarchy-plymouth-set` to change theme
- `omarchy-plymouth-preview` to test
- `omarchy-plymouth-reset` to restore

### 20.2 SDDM Login Manager

- Minimal themed greeter
- Hyprland-based session selector
- Theme syncs with active Omarchy theme

### 20.3 Btrfs + Snapper

- Btrfs filesystem with subvolumes
- `omarchy-snapshot` — Create manual snapshot
- Snapper automatic snapshots (timeline)
- Rollback capability

### 20.4 Full-Disk Encryption

- LUKS encryption on all installations
- Optional TPM2 unlock (hardware-dependent)

### 20.5 Udev Rules

Hardware-specific udev rules for:
- Graphics cards (Intel, NVIDIA, AMD)
- Touchpads (various vendors)
- External monitors (hotplug detection)
- Bluetooth adapters

### 20.6 System Limits

Installation raises several limits:
- **File descriptors**: 2,097,152 (`fs.file-max`)
- **inotify watchers**: 524,288
- **sudo tries**: Increased
- **plocate**: Only updates on AC power

### 20.7 SSH

`ssh-flakiness.sh` fixes common SSH connection issues with keepalive settings.

### 20.8 Timezone

`omarchy-tz-select` provides an interactive timezone picker launched from the clock right-click.

### 20.9 Docker

Docker is configured with socket activation (starts on demand, not at boot) to save resources.

---

## Architecture Summary

| Layer | Technology | Role |
|---|---|---|
| **OS Base** | Arch Linux | Rolling release foundation |
| **Compositor** | Hyprland (Wayland) | Window management |
| **Display Manager** | SDDM | Login greeter |
| **Boot Loader** | Limine | System boot |
| **Boot Splash** | Plymouth | Visual boot |
| **Session Manager** | UWSM | App lifecycle |
| **Status Bar** | Waybar | Info display |
| **Launcher** | Walker | App launching |
| **Notifications** | Mako | Alert display |
| **Terminal** | Alacritty (default) | Shell access |
| **Lock Screen** | Hyprlock | Session lock |
| **Idle Manager** | Hypridle | Auto-lock/suspend |
| **Audio** | PipeWire + WirePlumber | Sound |
| **Input Method** | Fcitx5 | Multilingual typing |
| **Clipboard** | cliphist | History |
| **Screenshots** | grim + slurp | Capture |
| **File Manager** | Nautilus | File browsing |
| **Theme System** | Custom shell scripts | 20 coordinated themes |
| **Update System** | Git + migrations | Safe updates |
| **CLI** | 234 bash scripts | Unified interface |
| **Config** | 3-layer (templates/defaults/user) | Flexible customization |
