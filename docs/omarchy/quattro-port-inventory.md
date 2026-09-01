# Quattro Port Inventory — live reference findings (2026-09-01)

**Source:** live inspection of the Omarchy 4.0.2 install on IVOKUN-HTPC
(`/usr/share/omarchy`; separate machine, not kebun-managed). Versions verified there:
`omarchy 4.0.2-1`, `omarchy-settings 4.0.2-1`, `quickshell 0.3.1-1`, `hyprland
0.56.2-1`, `aether 4.29.8-1`. Note: that install was upgraded to quattro on
2026-09-01, so its `~/.config/hypr/` still contains stale `.conf` files with dead
`source =` lines — the live entry is `hyprland.lua`.

This is the requirements document for ADR-0007 Stages 2–5.

---

## 1. Shell loader mechanics

### Startup chain
1. **Hyprland entry**: `~/.config/hypr/hyprland.lua` → `dofile($OMARCHY_PATH/default/hypr/bootstrap.lua)` → `require("default.hypr.omarchy")`.
2. **Autostart**: `/usr/share/omarchy/default/hypr/autostart.lua` — inside `hl.on("hyprland.start", ...)`:
   - `hl.exec_cmd("omarchy-launch-shell")` (plain exec, **not** uwsm-wrapped — unlike `o.launch()` which wraps everything else in `uwsm-app --`)
   - then `omarchy-provision-first-run`, `omarchy-powerprofiles-init`, `o.launch("omarchy-hyprland-monitor-watch")`, `udiskie`, `omarchy-hook post-boot`.
3. **`omarchy-launch-shell`** (`/usr/share/omarchy/bin/omarchy-launch-shell`): a supervisor loop. The actual launch command:
   ```
   QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 systemd-cat -t omarchy-shell -- quickshell -n -p "$OMARCHY_PATH/shell"
   ```
   Restarts on nonzero exit (5 attempts/min window), verifies compositor liveness via `hyprctl -j monitors`, exits on signals. File watcher is disabled so package upgrades can't hot-reload a half-written tree.
4. **`omarchy-restart-shell`**: `quickshell kill -p "$OMARCHY_PATH/shell" --any-display` in a loop, then relaunches via `hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'` so the shell inherits canonical session env. Lock-aware (refuses/relocks). Recovers `WAYLAND_DISPLAY` / `HYPRLAND_INSTANCE_SIGNATURE` when called from SSH/TTY.

### The programmatic IPC surface (what a port must replicate)
**`omarchy-shell`** (`/usr/share/omarchy/bin/omarchy-shell`) is the universal IPC wrapper — a NixOS port's scripts need exactly this command:
```
omarchy-shell [-q] <target> <method> [args...]
# implementation: timeout $OMARCHY_SHELL_IPC_TIMEOUT qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@"
```
`-q` = best-effort quiet mode (exit 0 when shell absent). Recovers `WAYLAND_DISPLAY` from the newest `wayland-[0-9]*` socket. Short-circuits `toggle`/`summon` with missing payload to `{}`.

**IPC targets registered** (from `grep 'target: "'` across `/usr/share/omarchy/shell/`):
- `shell` — the host target (see below)
- `osd` (`show` with JSON `{icon,message,value,progressText,max,duration}`)
- `lock` (`lock`, `status` → `{secure,requested}`)
- `notifications` (`dismissOne`, `dismissAll`, `invokeLast`, `showHistory`)
- `background` (`themeTransition old next final colorsB64 shellB64`)
- `idle`, `nightlight`, `media`
- Per-bar-widget targets: `omarchy.bar` (`syncHidden`), `omarchy.indicators`, `omarchy.clock`, `omarchy.bluetooth`, `omarchy.monitor`, `omarchy.network`, `omarchy.power`, `omarchy.system-update`
- `image-selector` (base64 payload picker protocol)

**`shell` target methods** (from `shell.qml`): `ping`, `summon <id> <payloadJson>`, `hide <id>`, `toggle <id>`, `call <id> <method> <arg>`, `rescanPlugins`, `reloadConfig`, `setPluginEnabled <id> <"true"|other>`, `enablePlugin <id> <placementJson>`, `putBarWidget`, `moveBarWidget`, `setBarWidget`, `listPlugins` (JSON), `listShellConfig`, `applyTheme <colorsB64> <shellB64>`, `toggleBarTransparency`, `togglePanelAt <section> <index>`, `debugBarGeometry`.

**The exact commands kebun-style scripts would call** (thin wrappers in `bin/`, all delegating to `omarchy-shell`):
| v4 command | Definition |
|---|---|
| `omarchy-menu [toggle\|summon\|close\|refresh\|ping] [route]` | `omarchy-shell shell toggle omarchy.menu '{"menu":"<route>"}'` etc. |
| `omarchy-osd -i <icon> -m <text> -p <0-100> -d <ms>` | builds JSON via jq → `omarchy-shell -q osd show <payload>` |
| `omarchy-notification-send [-g glyph] [-u urgency] [-t ms] [-r id] [--exec ...] <headline> [desc]` | full notify-send-compatible flags parser → notifications plugin |
| `omarchy-toggle-bar [toggle\|on\|off]` | writes toggle flag + `omarchy-shell -q omarchy.bar syncHidden` |
| `omarchy-system-lock` | `omarchy-shell lock lock` + `hyprctl switchxkblayout all 0` + 1password lock |
| `omarchy-shell shell toggle omarchy.emojis` | direct (used by bindings) |
| `omarchy-shell notifications dismissOne` | direct (used by bindings) |

### shell.json schema and readers
- **Default**: `$OMARCHY_PATH/config/omarchy/shell.json`; **User**: `~/.config/omarchy/shell.json`. Read by `shell.qml` via Quickshell `FileView { watchChanges: true }` — live reload, atomic writes. **No deep-merge**: a valid user file (`version: 1` required) fully replaces defaults; parse failure falls back to defaults; a builtin config object is the last resort.
- Schema (live example read from the reference machine):
  ```json
  { "version": 1,
    "idle": { "screensaver": 150, "lock": 300 },
    "bar": { "id": "omarchy.bar" (implicit), "position": "top", "transparent": false,
             "centerAnchor": "omarchy.clock",
             "layout": { "left":   [{"id": "omarchy.menu"}, {"id":"omarchy.workspaces"}],
                         "center": [{"id":"omarchy.indicators"}, {"id":"omarchy.clock","format":...,"verticalFormat":...}, ...],
                         "right":  [{"id":"omarchy.tray"}, ...] } },
    "plugins": [],
    "disabledPlugins": [],        // optional: disabling a first-party non-widget records here
    "cloneSourceRestores": [] }   // optional, clone bookkeeping
  ```
  Inline settings live directly on each layout entry (e.g. `format` on the clock). Written back by `persistShellConfig()` via `shellConfigMutator`.

### Plugin resolution
`/usr/share/omarchy/shell/services/PluginRegistry.qml`:
- **First-party scan**: `$OMARCHY_PATH/shell/plugins` via a bash subprocess: `find <dir> -mindepth 2 -maxdepth 3 -type f ( -name manifest.json -o -name '*.manifest.json' )` — so `plugins/panels/audio/`, `plugins/services/battery/` grouping works. Shipped plugin dirs: `agents, background, bar, clipboard, dev-gallery, emojis, image-picker, lock, menu, notifications, osd, panels/{audio,bluetooth,monitor,network,power,weather,clock,...}, polkit, reminders, services/{battery,idle}`.
- **Third-party scan**: `~/.config/omarchy/plugins/*/manifest.json`. Manifest = `schemaVersion: 1`, required `id,name,version,kinds,entryPoints`; kinds: `bar-widget | panel | overlay | menu | service | bar`; entry points are relative paths validated against path traversal; `omarchy.*` id namespace is reserved (third-party can't shadow).
- **Enabled state**: bar widgets = present in `bar.layout.*`; other third-party = present in `plugins[]`; first-party non-bar = enabled unless in `disabledPlugins[]`; bar options = `bar.id`.
- **Hot reload**: `inotifywait -m -r -e close_write,create,delete,move` on `~/.config/omarchy/plugins` (inotifywait is a hard runtime dep) + `omarchy-shell shell rescanPlugins`.
- Plugin management CLI: `omarchy-plugin-add/enable/disable/list/update/clone/validate/remove` (git-clone installs, `--yes` non-interactive mode).

---

## 2. Theme engine (and where aether actually fits)

- **Omarchy's own engine is separate from aether.** `omarchy-theme-set <name>`:
  1. Stages `/usr/share/omarchy/themes/<name>/` + user overlay `~/.config/omarchy/themes/<name>/` into `~/.local/state/omarchy/current/next-theme` (denies `*.lua`, `alacritty.toml`, terminal configs, `vscode.json` from repo-installed themes as arbitrary-code vectors).
  2. `omarchy-theme-set-templates` renders `$OMARCHY_PATH/default/themed/*.tpl` (17 files: `alacritty.toml, btop.theme, chromium.theme, claude.json, foot.ini, ghostty.conf, gum_env.lua, helix.toml, hyprland.lua, hyprland-preview-share-picker.css, keyboard.rgb, kitty.conf, neovim.lua, obsidian.css, pi.json, shell.toml, vscode-theme.json`) using `colors.toml` as the palette (with `hex→rgb`, `mix_color`, gradient support).
  3. Atomically swaps to `~/.local/state/omarchy/current/theme/`, pushes the live palette into the running shell via `omarchy-shell shell applyTheme <b64 colors.toml> <b64 shell.toml>` and `background themeTransition`.
  4. Runs `post_theme_commands` in parallel: restart-terminal/hyprctl/btop/opencode/helix, theme-set-{foot,tmux,gnome,pi,claude,browser,vscode,obsidian,keyboard}, then `omarchy-hook theme-set` (`~/.config/omarchy/hooks/theme-set.d/`).
  5. Headless mode via `OMARCHY_THEME_HEADLESS=1` / `OMARCHY_THEME_OFFLINE=1` (used during ISO chroot).
- **Palettes**: the 22 shipped themes live in `/usr/share/omarchy/themes/` (catppuccin, catppuccin-latte, ethereal, everforest, flexoki-light, gruvbox, hackerman, kanagawa, last-horizon, lumon, lupine, matte-black, miasma, nord, osaka-jade, retro-82, ristretto, rose-pine, solitude, tokyo-night, vantablack, white). Format per theme: `colors.toml` (semantic keys + 16-color ANSI), `backgrounds/`, `icons.theme`, `keyboard.rgb`, `neovim.lua`, `shell.lock.toml`, `preview.png`, `vscode.json`. The current staged theme (verified live) also contains the 17 generated outputs. `omarchy-theme-color` is the shared palette resolver CLI (`--all`, `--raw`, `<key> [fallback]`, alias cascade, dark/light mode detection).
- **Aether** (`aether 4.29.8-1`, own package, Go + Wails v2 with embedded Svelte frontend, deps webkit2gtk-4.1/gtk3) is an **optional** GUI palette engine. Headless modes exist (`--generate <wallpaper> [--no-apply] [--output <path>]`, `--extract-palette`, blueprint import/export, `set-palette <json>`), and its own state lives in `~/.config/aether/`. Its generated targets are the **v3 app set** (`foot.ini, mako.ini, wofi.css, warp.yaml, btop.theme, kitty.conf, neovim.lua, walker.css, waybar.css, zellij.kdl, swayosd.css, hyprland.conf, hyprlock.conf, alacritty.toml, …`) — not the quickshell shell. It can register itself as an omarchy theme (`~/.config/omarchy/themes/aether/`) to participate in `omarchy-theme-set`. **Not in nixpkgs; not needed for the port** — Stage 5 ports omarchy's template engine.

---

## 3. Hyprland Lua layer

### File tree of `/usr/share/omarchy/default/hypr/`
```
bootstrap.lua            # package.path setup + reload-safe module clearing
paths.lua                # {home, config_home, state_home, omarchy_path} table
helpers.lua              # ★ the o.* API (o.bind, o.launch, o.window, ...)
omarchy.lua              # master require: helpers, autostart, bindings/*, envs,
                         #   looknfeel, input, windows, theme override (optional)
autostart.lua            # hl.on("hyprland.start") — shell, provision, monitor-watch
envs.lua                 # hl.env (Wayland vars, XCURSOR, XCOMPOSEFILE, OMARCHY_PATH,
                         #   PATH prepends $OMARCHY_PATH/bin), hl.config(xwayland…)
looknfeel.lua  input.lua  windows.lua  nvidia.lua  workspace-layouts.lua
disabled-input-device.lua
apps/  apps.lua          # per-app window rules, require_all'd
bindings/  bindings.lua  # media clipboard tiling utilities voxtype applications
require_all.lua          # M.files(dir, prefix, {exclude=, reload=})
require_optional.lua     # M.module(name) — require only if findable
toggles/  toggles.lua    # loads ~/.local/state/omarchy/toggles/hypr/*.lua
```

### The `o.bind` API (defined in `helpers.lua`)
```lua
o.bind(keys_string, description, dispatcher, options)
-- keys:  "SUPER + SPACE", "SUPER + SHIFT + code:201", "XF86PowerOff", "switch:on:Lid Switch"
-- dispatcher: string → wrapped as hl.dsp.exec_cmd(cmd); or table resolved by command_from():
--   {omarchy="menu"} → "omarchy-launch-" .. value.omarchy
--   {focus=, launch=} → o.launch_sole() → omarchy-launch-or-focus 'match' 'uwsm-app -- cmd'
--   {launch=}  → o.launch(cmd) → "uwsm-app -- " .. cmd
--   {webapp=}  → omarchy-launch-webapp / omarchy-launch-or-focus-webapp
--   {tui=}     → omarchy-launch-tui / omarchy-launch-or-focus-tui
-- options: {locked=true, description=…} passed to hl.bind
o.bind_toggle(keys, desc, "bar")          -- → "omarchy-toggle-bar"
o.notify(msg)                             -- → "omarchy-notification-send -u low 'msg'"
o.window(match, rules)                    -- → hl.window_rule (match.class etc.)
o.exec_on_start / o.launch_on_start / o.cmd_present / o.shell_succeeds
```
`hl.*` is **Hyprland 0.56's native Lua API** (`hl.on`, `hl.exec_cmd`, `hl.bind`, `hl.env`, `hl.monitor`, `hl.window_rule`, `hl.config`, `hl.dsp.exec_cmd`) — no external shim. Binding style is declarative-with-description (replaces v3's `bindd`), e.g. `o.bind("SUPER + ESCAPE", "System menu", "omarchy-menu toggle system")`.

### Config sourcing & override model
- `~/.config/hypr/hyprland.lua` (5-line user file): `dofile(bootstrap.lua)` → `require("default.hypr.omarchy")` → `require("hypr.monitors")`, `require("hypr.input")`, `require("hypr.bindings")`, `require("hypr.looknfeel")`, `require("hypr.autostart")` → `require("default.hypr.toggles")` → `require("hyprmon")`. User modules load **after** defaults; kill-switches: `_G.omarchy_default_bindings = false`, `omarchy_preinstalled_bindings = false`.
- `bootstrap.lua` sets `package.path = ~/.local/state/?.lua; ~/.config/?.lua; $OMARCHY_PATH/?.lua` and unloads `default.hypr.*`/`hypr.*`/`omarchy.current.theme.*` modules on reload. Theme override is `omarchy.current.theme.hyprland` — generated from the staged theme's `hyprland.lua` (template `default/themed/hyprland.lua.tpl` → `~/.local/state/omarchy/current/theme/hyprland.lua`).
- **Monitors**: `~/.config/hypr/monitors.lua` (hand-edited, `hl.monitor({output=, mode=, position=, scale=, transform=})`) and `~/.config/hypr/hyprmon.lua` (header: "Generated by HyprMon. Manual changes may be overwritten") — hyprmon writes profiles as `hl.monitor({...})` calls; required as the last monitor source.
- Runtime toggles land as generated Lua in `~/.local/state/omarchy/toggles/hypr/` (loaded by `toggles.lua` via `require_all`, with a security exclusion list for legacy injected files).

### Minimal file set for a working config
The defaults tree is self-contained; a port can vendor it wholesale. Absolute minimum: `bootstrap.lua` + `paths.lua` + `helpers.lua` + `omarchy.lua` (+ whatever defaults `omarchy.lua` requires: autostart, envs, looknfeel, input, windows, bindings/*, apps) — i.e. effectively the whole directory, ~20 files, plus the 5-line `~/.config/hypr/hyprland.lua`. There are **no `.conf` files left** in `default/hypr/`; Hyprland 0.56.2 (verified: `hyprctl version` → v0.56.2) loads `hyprland.lua` when present.

---

## 4. Port surface — kebun scripts (`packages/scripts/default.nix`, ~70 scripts)

### Scripts calling **walker** (`walker --dmenu`)
| Script | Does | v4 replacement |
|---|---|---|
| `menu-keybindings` | `hyprctl -j binds` + jq → walker dmenu cheatsheet | `omarchy-menu-keybindings` (menu plugin); still viable as-is if walker is kept through the transition |
| `menu-capture` | picker → screenshot/OCR/record | `omarchy-menu toggle capture` route |
| `menu-toggle` | picker → toggles | `omarchy-menu toggle toggle` route |
| `menu-hardware` | picker → audio/bt/wifi/power/brightness/volume | `omarchy-menu toggle hardware` route |
| `menu-omarchy` | picker → apps/lock/keybindings | `omarchy-menu toggle root` route |
| `menu-background` | picker → swaybg solid colors | `omarchy-menu toggle background` (quickshell background plugin) |
| `screenrecord-menu` | picker → record region/screen/stop | `omarchy-menu toggle trigger.capture.screenrecord` pattern |
| `reminder-set` | text input via walker dmenu | `omarchy-menu-input` / quickshell input plugin |
| `transcode` | picker + 3× file pickers | `omarchy-menu-file` / `omarchy-file-select` |

### Scripts touching **elephant**
| Script | Does | v4 replacement |
|---|---|---|
| `restart-walker` | pkill walker; restart elephant unit; relaunch walker --gapplication-service | **not needed** — no elephant/walker in the v4 stack |

### Scripts touching **waybar**
| Script | Does | v4 replacement |
|---|---|---|
| `toggle-waybar` | systemctl --user start/stop waybar | `omarchy-toggle-bar` (toggle flag + `omarchy-shell -q omarchy.bar syncHidden`; bar never dies, just hides) |
| `restart-waybar` | systemctl --user restart waybar | **not needed** (`omarchy-restart-shell` restarts everything) |
| `check-waybar-updates` | JSON module output for waybar | **not needed** — `omarchy.system-update` bar widget is built into shell.json layout |

### Scripts touching **mako**
| Script | Does | v4 replacement |
|---|---|---|
| `toggle-dnd` | `makoctl mode -t do-not-disturb` + notify | `omarchy-toggle-notification-silencing` |
| ~20 scripts call `notify-send` directly (battery-monitor, mic-mute, screenrecord, audio-switch, toggle-gaps, toggle-layout, cycle-monitor-scaling, reminder-*, dictation-*, transcode, cursor-zoom, show-battery/time/weather, toggle-laptop-display, toggle-mirror-display…) | libnotify toasts | swap to `omarchy-notification-send` (same flags: `-u`, `-t`, `-r`, `-i`, `--exec`) |

### Scripts touching **swayosd**
| Script | Does | v4 replacement |
|---|---|---|
| `menu-hardware` | `swayosd-client --brightness/--output-volume raise|lower` | `omarchy osd -i brightness -p N` via `omarchy-brightness-display` / `omarchy-audio-output-volume` |

### Scripts touching **hyprlock**
| Script | Does | v4 replacement |
|---|---|---|
| `hyprlock-guard` | output-repair + flock + exec hyprlock | **not needed as-is** — v4 lock is a quickshell plugin (`omarchy-shell lock lock`, ext-session-lock with relock/status protocol); keep the "repair zero-output" prologue inside a port lock wrapper if the dpms edge cases are retained |
| `menu-omarchy` "Lock screen" | direct `hyprlock` | `omarchy-system-lock` |
| `lock-screen` | `loginctl lock-session` | keep (logind path still valid) |

### Scripts touching **hypridle**
| Script | Does | v4 replacement |
|---|---|---|
| `menu-toggle` "Idle locking" | `hypridle --toggle` | `omarchy-toggle-idle` (idle timings live in shell.json `idle:{screensaver,lock}`; idle is a first-party service plugin) |

**Remaining scripts with no v4 overlap** (port unchanged): all grim/slurp/tesseract captures, pactl audio, battery readers, hyprctl-only scripts (window-pop, close-all-windows, cycle-monitors, cycle-monitor-scaling, toggle-gaps, toggle-layout, toggle-single-window-square, toggle-laptop-display, toggle-mirror-display, launch-or-focus/launch-tui family, wake-display), nix flake checks, dictation (hyprwhspr-rs), transcode ffmpeg logic, cursor-zoom (hyprmag — v4 has no magnifier plugin; keep).

---

## 5. Quickshell invocation

- **Binary**: `/usr/bin/quickshell`, symlink `/usr/bin/qs` (same package). `Quickshell 0.3.1 (revision , distributed by Arch Linux)`.
- **No git pin**: `/etc/pacman.conf` has only `[core] [extra] [multilib] [omarchy]` (Server `https://pkgs.omarchy.org/stable/$arch`). `install/omarchy-base.packages` lists plain `quickshell` from the official repo — quickshell **0.3.1 stable, not -git**.
- **Exact launch** (from `omarchy-launch-shell`):
  ```
  QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 systemd-cat -t omarchy-shell -- quickshell -n -p "$OMARCHY_PATH/shell" &
  ```
  `-n` = no duplicate instance; `-p` = config path (also the instance identity used by `qs ipc -p` and `quickshell kill -p <dir> --any-display`).
- **IPC**: `qs ipc -n -p "$OMARCHY_PATH/shell" call -- <target> <method> [args...]` (with `--` to protect shadowed subcommands; `timeout` + `--kill-after` guard; "Not ready to accept queries yet" distinguishes a starting shell).
- **QML import paths**: no `QML2_IMPORT_PATH`/`QML_IMPORT_PATH` env anywhere in the tree. Imports in the shell are `import Quickshell…` (resolved from `/usr/lib/qt6/qml/Quickshell/` — Bluetooth, DBusMenu, IpcHandler, Io, etc.) and `import qs.Commons` / `qs.Ui` / `qs.Services` — the `qs` namespace maps to the **`-p` config root**, i.e. `$OMARCHY_PATH/shell/`. Required runtime deps found in the code: `inotifywait` (plugin hot-reload), `jq` (payload builders), `bash`. Everything else (Pipewire, UPower, NetworkManager/hyprland IPC) is accessed via Quickshell modules.
- **Env contract**: `OMARCHY_PATH` must be in the session environment (uwsm/systemd user env; also force-set via `hl.env("OMARCHY_PATH", …)` in `envs.lua`, which also prepends `$OMARCHY_PATH/bin` to `PATH`). `omarchy-restart-shell` falls back to reading `OMARCHY_PATH` from `systemctl --user show-environment` for out-of-session callers.
- **Process supervision summary**: one Quickshell instance per graphical session hosting bar+panels+lock+osd+notifications as in-process plugins; `omarchy-launch-shell` is the supervisor (5 restarts/min budget, compositor-alive check); `omarchy-restart-shell` is the controlled restart path (lock-aware, re-invites pending toast services).

---

## Port-relevant constraints for kebun

1. Everything kebun calls (`omarchy-shell`, `omarchy-menu`, `omarchy-osd`, `omarchy-notification-send`, `omarchy-system-lock`, `omarchy-toggle-*`) is just bash over `qs ipc` — kebun can keep its script architecture and re-point the menus/OSD/notification/lock calls at these IPC verbs.
2. The `o.bind` Hyprland-Lua layer is a clean porting seam: kebun's `bindd` list in `home/features/hyprland.nix` maps 1:1 onto `o.bind(keystr, desc, dispatcher)` lines.
3. Theme: kebun's per-file Rose Pine duplication maps onto one `colors.toml` + the `omarchy-theme-set-templates` model (or `omarchy-theme-color --file` in scripts) rather than aether (which targets the v3 app set).
4. Walker/elephant/waybar/mako/swayosd drop out entirely; hyprlock/hypridle drop out in favor of the shell lock/idle plugins — but the hard-won invariants in `hyprlock-guard`/`wake-display`/`toggle-laptop-display` (zero-output unsafe state, session-lock inertness) still apply to the quickshell lock plugin and are worth carrying over.
5. Kebun diverges deliberately on the raw `exec` for the shell launch: v4's autostart uses `hl.exec_cmd("omarchy-launch-shell")` unwrapped; kebun's UWSM mandate requires `uwsm app --` wrapping (CLAUDE.md gotcha).
