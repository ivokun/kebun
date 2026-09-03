# Omarchy → NixOS (Kebun) Discrepancy Analysis

**Status (2026-09-03):** this document is the audit snapshot of 2026-09-01 that fed
ADR-0007. The Quattro migration has since **completed** per ADR-0007 — see the ADR's
Outcome note and the post-migration addendum in `docs/omarchy-parity-backlog.md` for
current state. Sections describing the v3 stack (waybar, walker/elephant, mako,
hyprlock/hypridle, the `bindd` list) are historical.

**Last updated:** 2026-09-01
**Omarchy reference:** **v4.0.2** (`omarchy 4.0.2-1` pacman package at `/usr/share/omarchy`),
live on **IVOKUN-HTPC** (hostname `ivokun-htpc`, a B550M desktop running Arch — a
separate machine, not kebun-managed): Hyprland 0.56.2, QuickShell 0.3.1, uwsm 0.26.7.
**Kebun reference:** working tree at commit `86592b7`; deploys to `sakura` only.

Findings were checked against the running v4 install (every v3-era component is
uninstalled and absent from the process table), against upstream release metadata, and
against a full re-inventory of the kebun tree. Items marked *unverified* are flagged.

---

## Headline: the reference machine runs Quattro — the line kebun tracks is frozen

The previous revision of this report (2026-08-27) treated v4 as a release to watch and
3.8.5 as the live reference. Both facts are now stale:

- **IVOKUN-HTPC ran `omarchy-upgrade-to-quattro` on 2026-09-01 at 14:57** (the
  `*.omarchy-upgrade-to-quattro.20260901145742.bak` files under `~/.config` timestamp it).
  Waybar, walker, elephant, mako, swayosd, hyprlock, and hypridle are all **uninstalled**;
  the desktop runs as one QuickShell process. Correction: this is the reference machine,
  not the machine kebun configures — earlier revisions of this report wrongly assumed a
  shared `$HOME` between the two.
- **The `master` (3.8.x) branch has received zero commits since the v3.8.5 tag on
  2026-08-14.** It is not backport-only; it is frozen.
- Upstream momentum is two **security-driven** patch releases in one week: v4.0.1
  (2026-08-25) and v4.0.2 (2026-08-31), from a newly formed Omarchy security team, with
  signed packages now required and a responsible-disclosure policy at omarchy.org/security.
  None of that work reaches 3.8.x.
- Upstream moved from `basecamp/omarchy` to **`omacom/omarchy`** (org rename; old URLs
  redirect).

**Consequence for kebun.** ADR-0007 is **accepted: migrate to Quattro, staged** (the
draft's hybrid recommendation rested on a shared-$HOME obstacle that does not exist —
the machines are separate). The reference implementation kebun mirrors receives
nothing — not even security fixes. Section 2 describes what v4 concretely is, now that
it can be inspected live instead of inferred from diffs; the staged plan and port
requirements are in the ADR and `docs/omarchy/quattro-port-inventory.md`.

---

## 1. Verified defects in kebun

### 1.1 Fixed since the 2026-08-27 audit

Re-verified in the tree at `86592b7`; all seven 2026-08-27 fixes are in place:

- `battery-monitor` now runs as a systemd user service (`Restart=always`)
- `swayosd-server` supervised as a user service, off `exec-once`
- `toggle-dnd` reads mako's resulting mode list instead of branching on exit status
- LocalSend ports 53317 TCP+UDP open in `hosts/common/networking.nix`
- `services.locate` (plocate) enabled in `hosts/common/core.nix`
- gnome-keyring daemon + PAM unlock wired in `hosts/common/desktop.nix`
- Power-profile udev rule matches both `Mains` and `USB` supply types

### 1.2 Still open from the last audit

- **`reminder-*` is still a passive notepad.** `reminder-set` appends a timestamped line to
  `$XDG_DATA_HOME/kebun-reminders.txt`; nothing ever fires. v4's `omarchy-reminder` does it
  properly with transient `omarchy-reminder-*.timer` systemd user timers (`show` reads
  `list-timers --output=json`, `clear` cancels, shell indicator refreshes). Three
  keybindings (SUPER+CTRL+R family) point at the notepad.
- **Hyprland version skew.** Verified by `nix eval` on 2026-09-01: the compositor is
  `0.54.0+date=2026-04-30_2ff5988` (the flake input, frozen since April) while every
  `hyprctl` call site in `packages/scripts/default.nix` resolves to nixpkgs' **0.56.0** —
  a 0.56 client against a 0.54 server. Decision pending in the backlog (§1.2 there); if
  the bump happens it must land on **≥0.56.2** — 0.56.0/0.56.1 are the
  invalid-`hyprctl -j binds`-JSON window.
- **Monitor layout is stale — and the live layout moved again.** `home/sakura.nix`
  declares `HDMI-A-1` (not in use) and a 4K `DP-2` with `bitdepth,10`/`vrr,2` dropped. The
  live v4 config (`~/.config/hypr/hyprmon.lua`, HyprMon-generated) is now
  `DP-1 2560x1440@59.95 at 1920x1440 scale 1.00` with **`DP-2` disabled outright**.

### 1.3 New defects found in this audit

Found by full re-inventory, all confirmed in-tree:

1. **Browser flags are written to the wrong path.** `home/common.nix:246,252` uses
   `home.file."config/brave-flags.conf"` / `"config/chrome-flags.conf"` — relative to
   `$HOME`, that is `~/config/…`, but Chromium reads `~/.config/brave-flags.conf`. The
   Wayland/IME flags are silently never applied.
2. **Waybar `custom/idle` can never render.** `home/features/waybar.nix:162` gates on
   `test -f /tmp/hypridle-disabled`; nothing in the repo ever creates that file (the idle
   toggle is `hypridle --toggle`, which keeps no state file).
3. **SUPER+XF86AudioMute is mislabeled.** `home/features/hyprland.nix:404` describes
   "Switch audio output" but runs `pamixer --default-source toggle` — that toggles
   *source* mute. Either the description or the command is wrong.
4. **The X webapp can never focus.** `home/features/webapps.nix:59` uses
   `match = "//x.com"`; Chromium's app_id is `chrome-x.com__-Default`, which does not
   contain `//x.com`. The binding always relaunches. Fix is `match = "x.com"`.
5. **`menu-omarchy` "Lock screen" bypasses `hyprlock-guard`.** It execs bare `hyprlock`,
   skipping the zero-output repair + flock supervision that SUPER+CTRL+L deliberately
   routes through.
6. **SUPER+SHIFT+RETURN duplicates Browser.** It sits in the launcher slot upstream uses
   for browser (v4: SUPER+SHIFT+RETURN *is* browser), so this may be deliberate — but
   kebun also has SUPER+B for browser, and the combo reads like "alternate terminal".
   Flagged for intent, not correctness.
7. **Four parallel battery implementations exist:** waybar's native `battery` module, the
   `battery-monitor` daemon, the `SUPER+SHIFT+Y` inline notify, and the `battery-*` script
   family (of which only `battery-remaining-time` has a live caller, via `show-battery`).
   Dead weight on PATH: `volume-toggle`, `brightness-toggle`, `audio-switch`, `mic-mute`,
   `battery-status`, `battery-capacity`, `battery-remaining`, `launch-floating-terminal`.

---

## 2. What v4 actually is — verified against the live install

This replaces the diff-inference in the previous revision. All of it is inspectable on
this machine.

### 2.1 The shell: one QuickShell process

`omarchy-launch-shell` runs `quickshell -n -p $OMARCHY_PATH/shell` under `systemd-cat`,
supervised by a bash `wait` loop with a crash-relaunch budget (5/min) and compositor
liveness checks. `-n` (no auto-reload) is deliberate: package upgrades rewriting the tree
mid-reload spawn a second engine generation that breaks IPC.

Everything v3 split across six daemons is a **plugin inside one QML engine**
(`shell/plugins/`, each with a `manifest.json`, six kinds: `bar`, `bar-widget`, `panel`,
`overlay`, `menu`, `service`):

| Plugin | Replaces |
|---|---|
| `bar` + `panels/*` (audio, bluetooth, clock, disk-speedtest, dropbox, monitor, network, power, speedtest, tailscale, weather, wifiqr) | Waybar + all its modules |
| `menu` + `services/AppLibrary.qml` | Walker + elephant (app index is **in-process**; menu structure is JSONC data with `when:` bash predicates, not a provider daemon) |
| `notifications` | mako (DND, history, invoke-last included) |
| `osd` | SwayOSD |
| `lock` | hyprlock (QuickShell `WlSessionLock`; PAM services `omarchy-lock-password` / `-fingerprint`) |
| `services/idle` | hypridle (exactly two timeouts: `idle.screensaver` 150s, `idle.lock` 300s) |
| `services/nightlight` | hyprsunset |
| `background` | swaybg |
| `polkit` | polkit-gnome agent |
| `clipboard`, `emojis`, `image-picker`, `reminders` | walker providers / new |
| `agents` | new: AI agent usage panel fed by `omarchy-agent-usage-*` collectors |

Persisted state is **one file**, `~/.config/omarchy/shell.json` (bar layout, idle
timeouts, disabled plugins); a valid user file fully replaces the shipped default — no
deep-merge. All control is IPC: `omarchy-shell` wraps `quickshell ipc` with verbs
`summon/hide/toggle/call/rescanPlugins/reloadConfig/togglePanelAt`. Third-party plugins
are git repos cloned into `~/.config/omarchy/plugins/`, hot-reloaded — inherently
un-declarative; a NixOS port would need to treat that dir as user state.

### 2.2 Hyprland config is Lua

`~/.config/hypr/hyprland.lua` → `dofile(bootstrap.lua)` (package.path + cache purge on
reload) → `require("default.hypr.omarchy")` → user `hypr.{monitors,input,bindings,
looknfeel,autostart}` → generated runtime toggles from `~/.local/state/omarchy/toggles/`
→ `hyprmon` profile.

`o.bind(keys, description, dispatcher, opts)` (`default/hypr/helpers.lua`):
- `description` feeds the keybindings menu (`nil` = unlisted) — same contract as kebun's
  `bindd` convention.
- Dispatchers can be **table specs**: `{omarchy="terminal"}`, `{launch="obsidian",
  focus="^obsidian$"}`, `{webapp=url}`, `{tui="btop"}` compile to the right
  `omarchy-launch-*` call. `o.launch()` wraps `uwsm-app --` centrally.
- Options map to bind flags: `{locked, repeating, release, mouse}`.
- Requires **Hyprland 0.56+** (the Lua API). Kebun's compositor is 0.54.0 — this alone
  gates any config-port.
- Uses **positional `code:NN`** for digit/workspace binds (kebun already does this) and
  supports things Nix attrsets can't express: closures as dispatchers (cursor zoom reads
  and re-sets `cursor.zoom_factor`), event-scoped bind lifetime (screenshot keys bound on
  `layer.opened` of the selection namespace, unbound on close).

The v4 keymap's user-visible deltas vs kebun: SUPER+SPACE opens the **root menu** (kebun:
walker apps); SUPER+ALT+SPACE = apps; window grouping is first-class (SUPER+G family —
kebun has these); SUPER+CTRL+1-9 toggles the Nth bar panel; media keys call
`omarchy-shell media *` (MPRIS via shell IPC, not playerctl); SUPER+C/V/X is a
terminal-aware universal clipboard (sends CTRL+Insert to `+terminal`-tagged windows).

### 2.3 Other stack substitutions

| v3 (kebun current) | v4 |
|---|---|
| wl-screenrec (kebun `screenrecord`) | **gpu-screen-recorder** (kms backend; webcam overlay window, merged desktop+mic audio, −14 LUFS normalize pass) |
| satty (kebun has it installed) | **tensaku** (`dev.tensaku.Tensaku`, the default screenshot editor) |
| iwd + impala | **NetworkManager + nmcli** (`omarchy-network-*`; kebun deliberately stays on iwd) |
| wiremix / pavucontrol (kebun: wiremix) | shell audio panel |
| bluetui (kebun) | shell bluetooth panel + `bluetoothctl`/`rfkill` |
| tmux | partly **herdr** ("terminal workspace manager for AI coding agents", SUPER+CTRL+RETURN; tmux bindings still shipped) |
| hyprwhspr-rs (kebun dictation) | **voxtype** (whisper, F9 PTT; optional, not installed here) |
| Foot is upstream's default terminal | kebun primary is Alacritty (foot unconfigured) |

### 2.4 New upstream components with no kebun counterpart

- **The omarchy theme engine** (correction: not aether). `omarchy-theme-set` stages
  `/usr/share/omarchy/themes/<name>/` (+ user overlay), renders 17
  `default/themed/*.tpl` targets (`alacritty/foot/ghostty/kitty`, btop, helix,
  neovim.lua, hyprland.lua, shell.toml, colors.toml, obsidian.css, vscode, chromium,
  keyboard.rgb, claude.json, …) from the theme's `colors.toml`, atomically swaps
  `~/.local/state/omarchy/current/theme/`, and pushes the live palette into the running
  shell over IPC (`applyTheme`, `background themeTransition`). 22 themes ship; the
  reference runs `rose-pine`. **This is exactly kebun's "theme is hardcoded and
  duplicated" problem, solved upstream.** *Aether* is a separate, optional GUI engine
  (Go/Wails, own package) targeting the v3 app set — not part of this path, not in
  nixpkgs, and not needed for the port.
- **herdr 0.8.2** — persistent terminal sessions for agent work. Kebun has no
  multiplexer in the default flow.
- **tensaku 0.28.0** — annotation in the capture pipeline (screenshot → click → edit).
- **The `omarchy` meta-CLI** — a self-documenting dispatcher that reads
  `# omarchy:summary/args/group` headers from all 428 scripts. Kebun's 62 scripts have no
  equivalent discoverability surface (SUPER+K covers bindings only).
- **`omarchy-crash-watch` + `omarchy-agent-crash`** — follows journald for
  systemd-coredump's MESSAGE_ID, raises a critical toast whose click opens the default
  coding agent on a diagnosis prompt. Kebun has the `diagnose-crash` skill and opencode —
  the wiring is missing, not the pieces.
- **Lock-before-suspend done properly** (`omarchy-system-sleep-lock` / `-monitor`): a
  `systemd-inhibit --mode=delay` watcher on logind's `PrepareForSleep`, requesting the
  lock and polling until `.secure`, with the total budget **derived from logind's own
  `InhibitDelayMaxUSec`**. Kebun's `before_sleep_cmd = loginctl lock-session` fires and
  forgets — no confirmation the lock actually landed before sleep. This pattern ports even
  though kebun's lock target is hyprlock.

### 2.5 Packaging (no NixOS analogue)

Omarchy ships as signed pacman packages (`omarchy` + `omarchy-settings`, version-locked)
across four channels — `stable`, `rc`, `edge`, `dev` — each backed by its own Arch mirror
snapshot. QuickShell ships as a **stable 0.3.1** package from the omarchy repo
(correction of the earlier "quickshell-git pin" claim — `pacman.conf` carries plain
`quickshell`, and `install/omarchy-base.packages` lists the official-repo package). All
of this is meaningless to NixOS; what transfers is the lesson: watch QuickShell
versions, and expect Qt6 ABI fragility.

**nixpkgs availability for the port:** `quickshell` 0.3.0 is packaged (the reference
runs 0.3.1 — verify plugin compatibility at Stage 2), along with
`gpu-screen-recorder` 6.0.1, `herdr` 0.8.2, and `voxtype` 0.7.5. **`aether` and
`tensaku` are not packaged** (and aether is not needed — see §2.4's correction: v4's
theme engine is omarchy's own template renderer).

### 2.6 Reference-machine context (correction, 2026-09-01)

An earlier revision of this section described a "shared $HOME" between the Arch install
and kebun, with an ownership conflict and a `.bak` graveyard as evidence. **The premise
was wrong: IVOKUN-HTPC is a separate machine** (hostname `ivokun-htpc`, B550M desktop).
Kebun is edited and built there but deploys only to `sakura`; nothing is shared. The
`~/.config/hypr` files being regular Arch-owned files with 13 timestamped `.bak` files
is simply the HTPC's own omarchy state and its v3→v4 migration residue — not an
HM-vs-omarchy conflict. The ADR-0007 "logically blocked" analysis, the ownership
treaty, and the activation tripwire derived from it are all void; migration is
unblocked. Also invalidated: the §1.2 "live monitor layout" observation (that was the
HTPC's monitors, not sakura's) and backlog items §0.8 and §2.5.

---

## 3. v4.0.1/v4.0.2 security hardening — what applies to kebun

Both patch releases were security waves. Per-item relevance:

| Upstream fix | kebun exposure |
|---|---|
| SSH: key-only auth, sshd disabled when no usable key (v4.0.2) | **kebun runs OpenSSH with `PasswordAuthentication` on** (`hosts/common/networking.nix`). Worth matching upstream: keys-only, or off. |
| CUPS hardened; automatic printer discovery (cups-browsed) removed (v4.0.2) | kebun runs CUPS with Avahi discovery and an open firewall. Reconsider whether discovery is needed. |
| Docker group opt-in (v4.0.1) | `ivokun` is in `docker` (root-equivalent). Deliberate, but note upstream now treats it as opt-in hardening. |
| Theme/app installer shell-injection fixes, webapp URL validation + desktop-entry escaping (v4.0.1/4.0.2) | kebun's `webapps.nix` is a static declarative list — structurally safe. No theme installer exists. |
| Hyprland Lua injection via USB device names (v4.0.1) | kebun isn't on Lua config; revisit if migrating. |
| Agents launch with auto-review instead of full bypass (v4.0.1) | kebun never shipped the `cx`/`cy` bypass aliases. Already aligned — keep it that way. |
| Signed packages required | N/A (Nix store is content-addressed). |

---

## 4. Portable v4 improvements worth porting

Ranked for this ThinkPad, independent of the Quattro-migration decision. Tracked as tasks
in `docs/omarchy-parity-backlog.md`.

1. **Real timed reminders** — §1.2. v4's `omarchy-reminder` (transient user timers +
   countdown `show` + `clear`) is the reference implementation. Small, self-contained.
2. **Lock-before-suspend with a budget** — §2.4. Complements kebun's existing
   hyprlock-guard saga (ADR-0004, ADR-0006) with the `PrepareForSleep` inhibitor half.
3. **`omarchy-capture-qr`** — region-grab → `zbarimg` (QR symbology only) →
   `wl-copy --sensitive` so otpauth secrets never hit clipboard history. Trivial.
4. **Crash-watch → agent** — §2.4. journald coredump follower + toast → opencode with a
   diagnosis prompt. All dependencies already on the system.
5. **Injection-safe notification-send** — v4 calls `org.freedesktop.Notifications.Notify`
   via `busctl` so hostile headlines can't be reparsed as options. The base call works
   against mako.
6. **UPower battery status** — `omarchy-battery-status` (percentage, health from
   energy-full vs design, humanized time) beats kebun's four raw-`/sys` implementations
   and would consolidate them (§1.3.7).
7. **Persistent Bluetooth power toggle** — rfkill soft-block as source of truth
   (systemd-rfkill restores across boots; BlueZ `Powered` never persists).
8. **Terminal config catch-up** — still missing from the last audit, still shipped in v4:
   ghostty `async-backend = epoll` (Hyprland-slowness workaround), `window-theme =
   ghostty`, `shell-integration-features = ssh-env` (terminfo over SSH); kitty
   `cursor_blink_interval 0`, `shell_integration no-cursor`; plus v4's uniform **CSI-u
   Shift+Enter** encoding across all four terminals (`CSI 13;2u`) so TUIs can distinguish
   it.
9. **Wireplumber bluez auto-connect rule** (`a2dp_sink a2dp_source` SPA-JSON) — kebun
   doesn't configure wireplumber at all; fixes BT headset reconnect friction.
10. **Persistent input-device toggle** — `omarchy-toggle-input-device` writes a state file
    the config reads at reload; survives restarts, unlike kebun's nothing.
11. **Per-window width memory** (`omarchy-hyprland-window-width`) — save/restore focused
    width per window+workspace (v4 binds it SUPER+Home / SUPER+ALT+Home).
12. **`menu-keybindings` upgrades** — `xkbcli compile-keymap` resolution of `code:`
    bindings (kebun uses `code:10..19` for workspaces and currently shows raw codes).
13. **Webapp icons** — v4's `omarchy-webapp-install` fetches and sanitizes icons into
    hicolor; kebun's desktop entries all say `google-chrome`.
14. **Wi-Fi QR share + password show** — v4 uses `nmcli --show-secrets`; kebun is on iwd,
    so port via `iwctl`/`/var/lib/iwd/*.psk`. The `WIFI:S:…:T:WPA;P:…;;` payload format is
    portable.
15. **`omarchy-menu-timezone` / weather-location persistence** — small QoL over kebun's
    stateless `show-weather`.

---

## 5. Confirmed non-issues

Carried forward, re-verified where the ground moved:

- **Opacity retune & `hyprctl -j binds` JSON fragility** — both remain coupled to a
  Hyprland 0.56 bump kebun hasn't done (compositor still 0.54.0, pinned 2026-04-30).
  kebun's current opacity values are *correct* for 0.54. If the bump happens: retune
  `0.97/0.9 → 0.985/0.96`, and know that 0.56.0/0.56.1 (not .2) emitted invalid binds
  JSON. v4's Lua configs additionally *require* 0.56+.
- **`initramfs_async=0`** — targets a kernel 7.1 initramfs race; kebun is on 6.18.40.
  Revisit when nixpkgs moves.
- **`pkill -9` for waybar** — kebun's systemd user service escalates on its own.
- **App-launcher keybindings** — kebun's SUPER+B/N/D/O matches your live scheme, not
  upstream's SUPER+SHIFT+* template. Note v4 *did* keep SUPER+SHIFT+RETURN = browser,
  which kebun also has (see §1.3.6 for the intent question).
- **Rose Pine Dawn** — v4's `rose-pine` theme is still the Dawn palette kebun hardcodes.
  The current live theme on this machine is `rose-pine`.
- **`cx`/`cy` permission-bypass aliases** — still do-not-port. Upstream itself softened
  this in v4.0.1 (auto-review instead of bypass).
- **Script count** — 428 v4 commands vs 62 kebun scripts, zero orphans in kebun (62/62
  installed). Roughly 100+ of v4's are pacman/channel/migration plumbing with no Nix
  meaning; ~50 are `install-*`/`remove-*` app installers.
- **iwd vs NetworkManager** — v4 switched to NM; kebun's iwd stance (ADR-0002) stands.
  NM-bound upstream commands (`omarchy-network-*`) are not portable as-is.
- **`qmk-hid`, limine, Plymouth switching, hibernation installers, factory reset,
  channels** — Arch/pacman/installer concerns, no NixOS analogue.

---

## 6. Revised parity assessment

The "parity vs 3.8.5" frame is dead — 3.8.5 is frozen and uninstalled on the reference
machine. Two axes now:

**Axis 1 — kebun's own correctness (independent of upstream):** 7 defects fixed since
2026-08-27; 3 carried open (reminders, hyprctl skew, monitors); **7 new ones found**
(§1.3), of which the browser-flags path and the X-webapp match are user-visible daily.

**Axis 2 — tracking v4:** structural, not incremental.

| Layer | kebun today | v4 reality | Gap type |
|---|---|---|---|
| Desktop shell | waybar + walker/elephant + mako + swayosd + hyprlock + hypridle + hyprsunset + swaybg + polkit-gnome (9 components) | one QuickShell process, plugin manifests, shell.json state, IPC verbs | **rewrite** (`waybar.nix`, walker wiring in `desktop.nix`, mako/swayosd/hyprlock/hypridle sections of `hyprland.nix`) |
| Hyprland config | Nix attrsets → hyprland.conf, `bindd` | Lua API, `o.bind` table-spec dispatchers, runtime toggles, hyprmon; requires Hyprland 0.56+ | **rewrite** (`hyprland.nix`) + compositor bump |
| Theme | Rose Pine Dawn hardcoded in ~12 files | aether generates 17 targets from one palette, live IPC push | high-value, **adoptable without v4** (Nix-generate the same tree) |
| Scripts | 62, zero orphans | 428, incl. genuinely new capability (crash-watch, reminders, capture-qr, sleep-lock budget) | **incremental** — §4 list ports one by one |
| Security posture | see §3 | two hardening releases | mostly small, apply now |

**Bottom line.** Decision made: **ADR-0007 accepted — migrate to Quattro, staged**
(compositor bump → shell derivations → Lua config → stack swap → theme engine →
cleanup). The hybrid recommendation is void: it rested on a shared-$HOME obstacle that
does not exist (§2.6). §1.3 items 1 and 4 are stack-independent — fix now; the
v3-component items are superseded by the Stage 4 stack swap. The port requirements are
in `docs/omarchy/quattro-port-inventory.md`; the staged plan and retained divergences
(iwd, Rose Pine Dawn, ghostty/kitty, kebun's script set, UWSM) are in ADR-0007.
