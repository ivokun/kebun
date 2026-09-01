# Omarchy Parity Backlog

Actionable follow-ups from the 2026-09-01 re-audit in `OMARCHY_DISCREPANCY_REPORT.md`
(Omarchy reference is **v4.0.2**, live on the separate reference machine IVOKUN-HTPC;
the 3.8.x line is frozen). Each item names the file to touch and what the change is, so
none of them require re-deriving the analysis.

**Decision (2026-09-01): ADR-0007 accepted — migrate to Quattro, staged.** This
backlog is now the migration checklist plus the port items that survive each stage;
the stage plan is in ADR-0007 and the port requirements in
`docs/omarchy/quattro-port-inventory.md`.

Items marked **blocked** need a decision or a hardware step only you can take.
Items marked *unverified* are plausible but were not reproduced.

---

## Done (2026-08-27)

- ~~`battery-monitor` never started~~ → systemd user service, `home/features/hyprland.nix`
- ~~swayosd-server unsupervised on `exec-once`~~ → user service with `Restart=always`
- ~~DND toggle always reported "silenced"~~ → `toggle-dnd` script + mako notify-send carve-out
- ~~LocalSend port 53317 closed~~ → `hosts/common/networking.nix`
- ~~`plocate` installed, `services.locate` never enabled~~ → `hosts/common/core.nix`
- ~~`gnome-keyring` installed, no daemon or PAM hook~~ → `hosts/common/desktop.nix`
- ~~Power-profile udev matched only `type=Mains`, missing USB-C PD~~ → `hosts/sakura/default.nix`

---

## 0. Defects found 2026-09-01 — small, independent

All confirmed in-tree during the re-inventory. Stack-independent items (1, 4) fix now;
items touching v3 components (2, 3, 5, 6, 7) are only worth fixing if the current stack
still ships after the ADR-0007 Stage 4 stack swap — check the stage status first.

1. **Browser flags written to the wrong path.** `home/common.nix:246,252` —
   `home.file."config/brave-flags.conf"` writes `~/config/brave-flags.conf`; Chromium
   reads `~/.config/brave-flags.conf`. Change both keys to `.config/...`. The Wayland/IME
   flags have never been applied.
2. **Waybar `custom/idle` can never render.** `home/features/waybar.nix:162` gates on
   `test -f /tmp/hypridle-disabled`, which nothing creates. Either have the idle toggle
   (currently `hypridle --toggle`, SUPER+CTRL+I / `menu-toggle`) write that file, or
   delete the module.
3. **SUPER+XF86AudioMute mislabeled.** `home/features/hyprland.nix:404` — description
   "Switch audio output", command `pamixer --default-source toggle` (source *mute*).
   Fix the description, or point it at a real sink switcher (`volume-toggle` exists but
   is currently dead weight — see item 7).
4. **X webapp never focuses.** `home/features/webapps.nix:59` — `match = "//x.com"` is not
   a substring of app_id `chrome-x.com__-Default`. Change to `match = "x.com"`.
5. **`menu-omarchy` "Lock screen" bypasses `hyprlock-guard`.**
   `packages/scripts/default.nix` — the menu entry execs bare `hyprlock`; route it through
   `hyprlock-guard` like SUPER+CTRL+L does.
6. **SUPER+SHIFT+RETURN duplicates Browser** (`home/features/hyprland.nix`, launcher
   block). v4 also maps this combo to browser, so this may be deliberate — confirm intent;
   if deliberate, no change.
7. **Battery/audio dead weight.** Consolidate: keep waybar's native `battery` module +
   `battery-monitor` + `show-battery`; drop or rewire `battery-status`,
   `battery-capacity`, `battery-remaining` (no callers), and the unreferenced
   `volume-toggle`, `brightness-toggle`, `audio-switch`, `mic-mute`,
   `launch-floating-terminal`. If any are kept, wire them into a binding or menu.

---

## 1. Decide first — these gate other work

### 1.1 Omarchy 4 / Quattro — **DECIDED: migrate, staged (ADR-0007 accepted 2026-09-01)**

The user accepted option 2, overriding the draft's hybrid recommendation (which rested
on a shared-$HOME premise that turned out false — the reference install is a separate
machine, IVOKUN-HTPC). Stage plan: compositor bump → shell derivations (quickshell +
vendored plugins/bin wrappers) → Hyprland Lua port → stack swap → theme engine →
cleanup. Retained divergences: iwd (ADR-0002), Rose Pine Dawn palette, ghostty/kitty,
kebun's own script set, UWSM mandate. Port requirements:
`docs/omarchy/quattro-port-inventory.md`.

### 1.2 Hyprland version skew — **being fixed in Stage 1**

Verified by `nix eval` on 2026-09-01: compositor `0.54.0+date=2026-04-30_2ff5988` (flake
lock frozen since April); `pkgs.hyprland` **0.56.0** for all ~60 `hyprctl` call sites.
Stage 1 does both halves at once: pin the `hyprland` input to `v0.56.2` and point every
script's `hyprctl` at the compositor package. Gates at the first sakura rebuild:
re-validate the ADR-0004 lock guard and the ADR-0006 suspend path; the opacity retune
(§2.1) lands in the same change.

---

## 2. Coupled to a Hyprland 0.56 bump — do NOT apply in isolation

### 2.1 Opacity retune

| `home/features/hyprland.nix` | now (0.54) | on 0.56+ |
|---|---|---|
| line ~199 (catch-all) | `0.97 0.9` | `0.985 0.96` |
| lines ~212-213 (browsers) | `1 0.97` | `1.0 0.985` |

### 2.2 `menu-keybindings` JSON fragility

`packages/scripts/default.nix` uses `hyprctl -j binds | jq` under `set -euo pipefail`.
Hyprland 0.56.0/0.56.1 emitted invalid JSON; 0.56.2 is fine (verified live on the Arch
side). A `|| true` fallback makes the script fail soft regardless. While in there: add
`xkbcli compile-keymap` resolution of `code:NN` bindings (v4's version does this) —
kebun's own workspace binds use `code:10..19` and currently display raw codes.

---

## 2.5 Leftover Omarchy desktop entries — N/A (premise corrected)

Originally framed as a shared-`$HOME` problem. The reference install is a separate
machine (IVOKUN-HTPC); its leftover `~/.config/hypr/*.bak.*` files and v4 webapp
desktop entries are the HTPC's own state and no concern of kebun's. Nothing to do here;
kept as a record of the correction.

---

## 3. Host config drift

### 3.1 Monitor layout — **premise corrected; verify on sakura**

`home/sakura.nix:11-15` declares an `HDMI-A-1` display and a 4K `DP-2`. The earlier
"live layout changed" observation was the **HTPC's** monitors (DP-1 2560x1440, DP-2
disabled) — irrelevant to sakura. Whether `home/sakura.nix` is stale can only be
checked on sakura itself; do that before editing.

### 3.2 Fingerprint unlock

Unchanged, three steps: `services.fprintd.enable = true` in `hosts/sakura/default.nix` →
rebuild + `fprintd-enroll` → flip `fingerprint.enabled = true` in `hyprland.nix`. The X13
Gen 1's Synaptics `06cb:00bd` may need `libfprint-tod`.

### 3.3 Renamed NixOS options (warnings on every eval)

Unchanged: `services.logind.*` → `services.logind.settings.Login.Handle*`;
`services.resolved.{dnssec,fallbackDns}` → `services.resolved.settings.Resolve.*`;
`home.pointerCursor` wants explicit `enable = true`; fzf/atuin Ctrl-R conflict.

---

## 4. Missing features, ranked by value on this laptop

v4-verified reference implementations exist on the reference machine (IVOKUN-HTPC,
`/usr/share/omarchy/bin/`) for most of these — read them before writing the Nix
version. Under the accepted migration these port as the Stage 4/5 script layer; items
1–8 are the near-term port list.

1. **Real timed reminders.** Port v4's `omarchy-reminder`: transient
   `systemd-run --user --on-active=<N>m` timers named `kebun-reminder-*`, `show` reads
   `list-timers --output=json` with countdown, `clear` cancels. Replaces the
   `$XDG_DATA_HOME/kebun-reminders.txt` notepad. Three bindings (SUPER+CTRL+R family)
   already point at the names.
2. **Palette single-sourcing (the aether lesson, without aether).** v4 solves kebun's
   "theme is hardcoded and duplicated" problem by generating ~17 per-app configs from one
   palette. kebun already has the palette attrset in `home/features/theme-rose-pine.nix`
   (used only within that file). Promote it to a shared module (e.g. `lib/palette.nix`
   imported via `let palette = import ...; in`), then replace the hardcoded hexes in
   `hyprland.nix`, `waybar.nix`, `terminals.nix`, `ghostty.nix`, `kitty.nix`, `btop.nix`,
   `helix.nix`, `starship.nix`, `fastfetch.nix`, `mpv.nix`, `editors.nix`,
   `home/nvim/lua/`, and the scripts in `packages/scripts/default.nix`. Accept
   rebuild-to-retheme (already true today); multi-theme *switching* stays out of scope.
3. **Lock-before-suspend with a budget.** Port the `omarchy-system-sleep-lock` pattern:
   `systemd-inhibit --what=sleep --mode=delay` watcher on logind `PrepareForSleep`,
   request lock, poll until secure, budget derived from logind's `InhibitDelayMaxUSec`,
   critical notify if the machine slept unlocked. Complements `hyprlock-guard` /
   `wake-display` (ADR-0004, ADR-0006) — those cover display-state races; this covers the
   lock never landing before sleep.
4. **Crash-watch → agent.** journald follower on systemd-coredump's MESSAGE_ID
   (`fc2e22bc…`), dedupe per program per 60s, critical toast whose click runs opencode
   with a diagnosis prompt (kebun already has the `diagnose-crash` skill). Wire as a
   systemd user service with a toggle flag.
5. **`capture-qr`.** grim+slurp region → `zbarimg` (QR symbology only) →
   `wl-copy --sensitive`. Add to `menu-capture`.
6. **Injection-safe `notification-send`.** busctl call to
   `org.freedesktop.Notifications.Notify` instead of `notify-send` where headline text is
   attacker-influenced (the crash-watch toast is exactly that case).
7. **UPower battery status.** Replace the raw-`/sys` battery implementations
   (item 0.7) with one `upower`-based script: percentage, health (energy-full vs
   design), humanized time-to-empty/full.
8. **Wi-Fi power-save toggle.** Iterate `/sys/class/net/*/wireless`, `iw dev $iface set
   power_save on|off`. iwd is already the stack.
9. **Persistent touchpad toggle.** v4 pattern: script writes a state file; config reads
   it at reload. kebun shape: script + a `device` rule rendered from a state check in
   `hyprland.nix` (or a `hyprctl keyword` + state file if Nix purity isn't worth it).
10. **Suspend-inhibit ("caffeine") toggle.** v4's `omarchy-toggle-idle` is a flag file
    the shell watches. kebun shape: flag file + `hypridle` listener skip, plus fix the
    waybar indicator (item 0.2) to read the same flag.
11. **Wallpaper images.** `menu-background` offers four solid colors; no image support;
    `home/sakura.nix:107` wiring still commented out. Self-contained slice of the
    theming gap; pairs naturally with item 2.
12. **Terminal config catch-up.** ghostty: `async-backend = epoll`, `window-theme =
    ghostty`, `shell-integration-features = ssh-env`. kitty: `cursor_blink_interval 0`,
    `shell_integration no-cursor`. Optional v4 addition: uniform CSI-u Shift+Enter
    (`CSI 13;2u`) across terminals so TUIs can distinguish it.
13. **Wireplumber bluez auto-connect.** Ship the `a2dp_sink a2dp_source` SPA-JSON rule;
    kebun doesn't configure wireplumber at all today.
14. **Window rules kebun lacks.** Picture-in-picture (float/pin/size/aspect, incl.
    Google Meet); 1Password `no_screen_share`; terminal tag matches only `Alacritty` —
    extend to ghostty/kitty/foot so the SUPER+C/V/X clipboard binds go terminal-aware
    everywhere.
15. **Richer capture.** `screenrecord` is silent; upstream supports desktop audio + mic +
    webcam overlay via **gpu-screen-recorder** (`gpu-screen-recorder` 6.0.1 is in
    nixpkgs — evaluate switching backends from wl-screenrec at the same time).
16. **Webapp icons.** Fetch per-site icons into hicolor at build time instead of
    `icon = "google-chrome"` for all ten entries.
17. **Wi-Fi QR / password show.** iwd port of `omarchy-network-qr`: read the PSK from
    `/var/lib/iwd/<ssid>.psk`, emit a `WIFI:S:…;T:WPA;P:…;;` QR (`qrencode`).
18. **Per-window width memory** (`omarchy-hyprland-window-width` pattern): save/restore
    focused width per window+workspace, bound SUPER+Home / SUPER+ALT+Home.
19. **Shell ergonomics.** `..`/`...`/`....`; `MANPAGER` through `bat`; SSH port-forward
    helpers; tmux dev-layout builders (`tdl`/`tdlm`/`tsl`). (v4's answer to
    agent-terminal workspaces is **herdr** — 0.8.2 is in nixpkgs if you want to try it;
    **voxtype** 0.7.5 is also packaged should the hyprwhspr-rs dictation ever need
    replacing.)

---

## 5. Security posture from v4.0.1/v4.0.2 worth matching

- **SSH:** kebun runs `PasswordAuthentication yes` (`hosts/common/networking.nix`).
  Upstream v4.0.2 is key-only and disables sshd when no usable key exists. Match: set
  `PasswordAuthentication = false` (you have keys), or disable `services.openssh` if
  unused.
- **CUPS:** upstream removed automatic printer discovery (cups-browsed) in v4.0.2. kebun
  runs CUPS with Avahi discovery + open firewall. Decide whether discovery is actually
  used; if not, tighten.
- **Docker group:** `ivokun` is in `docker` (root-equivalent). Upstream made it opt-in.
  Deliberate here, but record the trade-off.
- No action needed: theme-installer injection (no theme installer), webapp entry escaping
  (`webapps.nix` is a static declarative list), USB-name Lua injection (not on Lua
  config), agent permission bypass (never shipped).

## 5b. System tuning worth considering

- `net.ipv4.tcp_mtu_probing=1` — SSH-flakiness fix
- `usbcore.autosuspend=-1` — USB peripheral dropouts
- `gtk-enable-primary-paste=true` — middle-click paste in GTK apps
- `DefaultTimeoutStopSec=5s` — caps shutdown stall
- Mask `systemd-networkd-wait-online.service` — boot hang with no link
- `MulticastDNS=no` in resolved — kebun runs resolved **and** avahi/`nssmdns4` concurrently
- **`system-sleep/unmount-fuse` hook** *(unverified)* — lazy-unmount `fuse.gvfsd-fuse`
  before sleep, restart `gvfs-daemon` after. Plausible contributor to the documented
  suspend/resume fragility (ADR-0006). v4 ships this same hook.
- Waybar indicators poll every 2s with `exec-if` where upstream pushes via `"signal": N` +
  `pkill -RTMIN+N waybar`. Functionally equivalent, but three `pgrep`/`makoctl` calls
  every two seconds, forever.

---

## 6. Explicitly not doing

- **NetworkManager migration.** v4 moved to NM; kebun stays on iwd (ADR-0002). NM-bound
  `omarchy-network-*` commands are not portable as-is.
- **v4 packaging/channel machinery** (`omarchy-update-*`, `pkg-*`, `channel-*`,
  `migrate`, `upgrade-to-quattro`, factory reset, provisioning) — pacman/ALPM concerns,
  no NixOS meaning.
- **`omarchy-hibernation-*`** — kebun's hibernation is deliberately off (8.8 GiB LUKS
  swap < 30.6 GiB RAM; see `hosts/sakura/default.nix`); if re-enabled it's declarative.
- **`aether` / `tensaku` as packages** — not in nixpkgs, and aether targets the v3 app
  set anyway; Stage 5 ports omarchy's own theme-template engine (colors.toml + *.tpl)
  instead. herdr/voxtype/gpu-screen-recorder *are* packaged — evaluate individually
  (items 15, 19).
- **`initramfs_async=0`** — kernel 7.1 race; kebun is on 6.18.40. Revisit at 7.1.
- **`pkill -9` for waybar** — kebun's user service escalates on its own.
- **`cx`/`cy` permission-bypass aliases** — do not port. Upstream softened this itself in
  v4.0.1 (auto-review, not bypass).
- **App-launcher keybindings** — kebun matches your live scheme, not upstream's template.
- **Bootloader, firewall mechanism, snapshots, `install-*` scripts** — systemd-boot +
  generations, declarative nftables, `/home`-only snapper, and module options remain
  correct NixOS substitutions.
