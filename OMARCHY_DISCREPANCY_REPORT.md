# Omarchy → NixOS (Kebun) Discrepancy Analysis

**Last updated:** 2026-08-27
**Omarchy reference:** v3.8.5 (`master`, commit `f4378f0d`), as installed live on this machine at
`~/.local/share/omarchy`, running Arch + Hyprland 0.56.2.
**Kebun reference:** working tree at commit `c2b4a28`.

Findings below were checked against the running Omarchy install and against `nix eval` on the
kebun flake, not inferred from documentation. Items marked *unverified* are flagged as such.

---

## Headline: the upstream line kebun tracks is now in maintenance mode

The previous revision of this document described Omarchy 4 as `v4.0.0.alpha`, in development.
That is no longer true:

- **v4.0.0 was released 2026-08-14**, and **v4.0.1 followed on 2026-08-25**.
- **`quattro` is now the repository's default branch** (`git ls-remote --symref origin HEAD`
  returns `refs/heads/quattro`). A stale `origin/HEAD` in an older local clone still points at
  `master` — don't trust that cache.
- Since the v4.0.0 tag, **`master` has received 1 commit; `quattro` has received 110.** The 3.8.x
  line is backport-only.
- 3.8.5 actively nags users to leave it: migration `1786465483.sh` fires a critical notification
  ("Upgrade to Omarchy Quattro"), wired through a new clickable `mako` rule to the new
  `omarchy-upgrade-to-quattro` command (2447 lines, shipped inside the 3.8.5 release itself).

**What v4 actually is.** `git diff --stat v3.8.4..v4.0.0` is 1876 files, +104k/−14k lines. Waybar
and walker are *gone* — `git ls-tree -r v4.0.0 | grep -iE 'waybar|walker'` returns nothing. The bar,
launcher, notifications, OSD, and lock screen are one QuickShell (Qt Quick/QML) application under
`shell/`. Every Hyprland config file is now `.lua` using Hyprland's native Lua API plus an
Omarchy `o.bind(keys, description, dispatcher)` wrapper. Omarchy itself now ships as pacman
packages from a dedicated repo across four channels.

**Consequence for kebun.** Tracking v4 is not incremental drift. It means re-deriving
`home/features/hyprland.nix` from Lua semantics instead of `.conf`/`bindd`, and replacing
`home/features/waybar.nix` plus the walker/elephant wiring with a QuickShell stack. That is a
rewrite of the two largest modules in the repo. Staying on 3.8.5 is defensible, but it is now
explicitly a decision to track a frozen branch, not a stable one.

---

## 1. Verified defects in kebun

These are not parity gaps — they are things that do not work as the config implies.

### 1.1 Four packages are installed but never wired up

A recurring pattern: the package lands in `PATH`, but nothing activates it.

| What | Where it's installed | What's missing |
|---|---|---|
| `battery-monitor` | `packages/scripts/default.nix:358`, listed in `home/common.nix:186` | Nothing launches it. Not in the `exec-once` list (`home/features/hyprland.nix:545-557`), and there are **no `systemd.user.services` anywhere under `home/`**. Low-battery warnings never fire. Omarchy runs the equivalent as `omarchy-battery-monitor.timer`. |
| `localsend` | `home/common.nix:62`, with a `localsend-share` script and a `SUPER CTRL+S` binding | `networking.firewall` opens only TCP `22 80 443` and no UDP ports (`hosts/common/networking.nix:24-25`). LocalSend needs **53317 TCP+UDP**. Sending may work; receiving cannot. |
| `plocate` | `home/common.nix:140` | `services.locate` is never enabled — no repo match outside that one package line. The database is never built, so `locate` returns nothing. |
| `gnome-keyring` | `home/common.nix:138` | No `services.gnome.gnome-keyring.enable`, no `security.pam.services.*.enableGnomeKeyring`. Omarchy additionally strips `pam_gnome_keyring.so` from SDDM's PAM stack and provisions a passwordless default keyring; kebun does neither. Keyring unlock at login is unconfigured. |

### 1.2 `reminder-*` looks ported but isn't

`reminder-set` / `reminder-show` / `reminder-clear` (`packages/scripts/default.nix:~780`) append a
timestamped line to `$XDG_DATA_HOME/kebun-reminders.txt` and `notify-send` the last 20 on demand.
It is a passive notepad — nothing ever fires.

Omarchy's `omarchy-reminder <minutes> [message]` schedules a real one-shot
`systemd-run --user --on-active=Nm` transient timer that raises a critical notification when it
elapses, with `show`/`clear` listing and cancelling live timers via `systemctl --user list-timers`.

Same three command names, three keybindings pointing at them, and materially different behaviour.
This is the single most misleading "PORTED" entry in the previous revision of this document.

### 1.3 The DND toggle always reports the wrong state

`home/features/hyprland.nix:416`:

```
makoctl mode -t do-not-disturb && notify-send 'Notifications silenced' || notify-send 'Notifications enabled'
```

The `&&`/`||` branch on `makoctl`'s **exit status**, not on the resulting mode. `makoctl mode -t`
succeeds in both directions, so this reports "Notifications silenced" every time the toggle works —
including when it is switching DND *off*. `makoctl mode -t` prints the resulting mode list on
stdout; the branch needs to read that.

### 1.4 Two different Hyprland versions are in play

Confirmed by `nix eval`:

- **Compositor:** `programs.hyprland.package` → `0.54.0+date=2026-04-30_2ff5988` (the `hyprland`
  flake input, pinned since 2026-04-30 and untouched by the last several `flake.lock` updates).
- **`hyprctl` CLI:** every one of the ~60 `hyprctl` call sites in `packages/scripts/default.nix`
  uses `${pkgs.hyprland}/bin/hyprctl`, which resolves to nixpkgs' **`0.56.0`**.

So the scripts drive a 0.56.0 client against a 0.54.0 server. This should be made consistent one
way or the other regardless of anything else in this report.

### 1.5 The monitor layout is stale

`home/sakura.nix:11-15` declares:

```
",preferred,auto,1"
"HDMI-A-1,1920x1080@60.00,2272x1440,1.00"
"DP-2,3840x2160@60.00,1920x0,1.5"
```

The live setup (`~/.config/hypr/hyprland.conf`) is:

```
monitor=DP-1,2560x1440@59.95,1920x1440,1.00
monitor=DP-2,3840x2160@60.00,1920x0,1.50,bitdepth,10,vrr,2
```

There is no `DP-1` entry in kebun, the `HDMI-A-1` entry describes a display that isn't in use, and
the `DP-2` line drops `bitdepth,10` and `vrr,2`.

---

## 2. Drift against Omarchy 3.8.5

### 2.1 The `hyprctl -j binds` breakage — narrower than it looks

Omarchy commit `05d6f489` rewrote `omarchy-menu-keybindings` to parse **plain-text** `hyprctl binds`
output with an awk state machine, because Hyprland 0.56 emitted invalid JSON from `hyprctl -j binds`.
kebun's `menu-keybindings` (`packages/scripts/default.nix:510`) still uses
`hyprctl -j binds | jq`, with no fallback and `set -euo pipefail` — so a malformed response aborts
the script with no menu at all, which is worse than Omarchy's degraded case.

**However, tested live on this machine (Hyprland 0.56.2): the JSON is valid.** 180 binds parse
cleanly, 178 carry descriptions. The breakage window was 0.56.0/0.56.1 and has since been fixed
upstream. Combined with kebun's compositor being 0.54.0, **this is not broken today.** It is a
landmine only if the Hyprland input is bumped to exactly 0.56.0 or 0.56.1.

### 2.2 Opacity retune — do NOT apply yet

Omarchy commit `bfab1a70` raised every opacity value (`0.97/0.9` → `0.985/0.96`, `1/0.97` →
`1.0/0.985`) because Hyprland 0.56 fixed an alpha-premultiplication bug that made old values render
more transparent than intended.

kebun still carries the pre-retune values (`home/features/hyprland.nix:199`, `212`, `213`). **This is
correct for kebun as it stands**, because kebun's compositor is 0.54.0. These two changes are
coupled: bump Hyprland to 0.56+ and the opacity values must move at the same time, or windows will
visibly wash out.

### 2.3 Power-profile udev rule misses the USB-C charging path

Omarchy fixed this in migration `1777098818` ("Fix power profile auto-switching on USB-C only
machines") by matching both supply types:

```
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+=...
SUBSYSTEM=="power_supply", ATTR{type}=="USB",   RUN+=...
```

kebun matches only `Mains`, in **both** the udev rule (`hosts/sakura/default.nix:156`) and the
detection loop inside the service (`hosts/sakura/default.nix:140`). On a USB-C PD supply that
enumerates as `type=USB`, the profile switch never fires. Worth a plug/unplug test on the dock.

*Note:* kebun is **immune** to the separate bug fixed by commit `749a8c04` (fixed transient unit
names colliding on resume). kebun dispatches to a persistent unit via `systemctl start --no-block`,
which is idempotent by construction. That is a place kebun's design is ahead of upstream.

### 2.4 SwayOSD is unsupervised

Omarchy migration `1778171768` deliberately moved SwayOSD *off* `exec-once` and onto a user unit
with `Restart=always`, `RestartSec=2`, `PartOf=graphical-session.target`. kebun still launches it
from `exec-once` (`home/features/hyprland.nix:553`) with no supervision — if it dies, volume and
brightness OSDs are gone until re-login. kebun also sets no `swayosd/config.toml`, so
`show_percentage` and `max_volume` sit at compiled-in defaults where Omarchy pins them.

### 2.5 Your live `~/.config` has drifted behind 3.8.5, and kebun inherited it

Because you customized these files, Omarchy's updater left them alone. Diffing shipped defaults
against your live copies surfaces upstream improvements that never reached either:

- **waybar** — missing the newer `custom/idle-indicator` and `custom/notification-silencing-indicator`
  modules and the `#custom-weather.unavailable` collapse styling; `custom/update` interval is 3600
  where upstream moved to 21600.
- **ghostty** — missing `window-theme = ghostty`, `gtk-toolbar-style = flat`, `async-backend = epoll`
  (a documented Hyprland-slowness workaround), and `shell-integration-features = ssh-env`, which is
  what makes terminfo work over SSH.
- **kitty** — missing `cursor_blink_interval 0` and `shell_integration no-cursor`.

### 2.6 Indicator modules poll where upstream signals

Omarchy's three waybar indicators declare `"signal": N` and are pushed by
`pkill -RTMIN+N waybar`. kebun's equivalents (`home/features/waybar.nix:143-183`) use
`interval = 2` with an `exec-if` guard, and no script in the repo ever signals waybar. Functionally
equivalent, but it is three `pgrep`/`makoctl` invocations every two seconds, forever.

---

## 3. Real gaps worth closing

Ranked for a single ThinkPad, in rough value-per-effort order.

1. **Wire up what's already installed** — §1.1. Four one-to-three-line fixes.
2. **Real timed reminders** — §1.2. systemd user timers are idiomatic on NixOS; the script is short.
3. **Wi-Fi power-save toggle** — `omarchy-wifi-powersave <on|off>` iterates `/sys/class/net/*/wireless`
   and calls `iw dev $iface set power_save`. Directly relevant to battery life, and kebun already
   runs iwd. Absent entirely.
4. **Touchpad enable/disable toggle** — `omarchy-toggle-touchpad` persists a
   `hyprctl keyword device[...]:enabled` state and shows an OSD. Absent.
5. **Suspend-inhibit ("caffeine") toggle** — no way to hold off suspend for a long build or a
   presentation without editing hypridle and rebuilding.
6. **Wallpaper images** — kebun's `menu-background` offers four solid colors and
   `swaybg -c '#faf4ed' -m solid_color`. There is no photo wallpaper support at all, and
   `home/sakura.nix:107` still has the wallpaper wiring commented out. This is a cheaper,
   self-contained slice of the theming gap and doesn't require multi-theme switching first.
7. **`system-sleep/unmount-fuse` hook** — Omarchy lazy-unmounts `fuse.gvfsd-fuse` before sleep and
   restarts `gvfs-daemon` after, to stop the freeze hanging. kebun runs Nautilus + gvfs and has
   documented suspend/resume fragility on this Renoir machine (ADR-0006, `hosts/common/core.nix:29-39`).
   Plausible contributor; worth testing before assuming it's unrelated. *Unverified.*
8. **Window rules kebun lacks** — picture-in-picture handling (float/pin/size/aspect) is absent
   entirely; 1Password has no `no_screen_share` rule; the terminal tag matches only `Alacritty`
   where Omarchy matches all four emulators.
9. **Richer share and capture** — `omarchy-menu-share` picks a file/folder/clipboard via fzf and
   sends headless; kebun's `localsend-share` only opens the GUI. `omarchy-capture-screenrecording`
   supports desktop audio, microphone, and webcam; kebun's records silent video only.
10. **`ALT+TAB` doesn't raise** — Omarchy binds `bringactivetotop` as a *second* bind on the same
    key alongside `cyclenext`. kebun binds only `cyclenext` (`home/features/hyprland.nix:346-347`),
    so alt-tabbed windows may not actually come forward.
11. **Shell ergonomics** — no `..`/`...`/`....` directory shortcuts; no `MANPAGER` (Omarchy pipes man
    pages through `bat`); no SSH port-forward helpers (`fip`/`dip`/`lip`); no tmux dev-layout builders
    (`tdl`/`tdlm`/`tsl`), which given how much agent work happens here is the most relevant of these.
12. **Misc system tuning** — `net.ipv4.tcp_mtu_probing=1` (SSH flakiness); `usbcore.autosuspend=-1`;
    `gtk-enable-primary-paste=true`; `DefaultTimeoutStopSec=5s`; masking
    `systemd-networkd-wait-online.service`; `MulticastDNS=no` in resolved, since kebun currently runs
    resolved *and* avahi/`nssmdns4` answering mDNS concurrently.

---

## 4. Confirmed non-issues

Things that look like drift but aren't, recorded so they don't get re-flagged:

- **App-launcher keybindings.** Omarchy's stock template moved app launchers to `SUPER SHIFT+*`, but
  your live `~/.config/hypr/bindings.conf` uses plain `SUPER+B/N/D/O`. kebun matches *your* scheme.
  Not stale — deliberate.
- **Fingerprint unlock disabled in hyprlock** (`home/features/hyprland.nix:660`). The live Omarchy
  install has it on, but kebun's `false` is deliberate and documented in place: `services.fprintd` is
  not enabled anywhere, so hyprlock was probing a D-Bus name that does not exist on every unlock.
  Enabling it is a three-step hardware task (enable `fprintd`, enroll, possibly add `libfprint-tod`
  for the X13's Synaptics `06cb:00bd`), tracked in §3 — not a one-line flip.
- **Rose Pine Dawn.** Omarchy's theme is named `rose-pine`, but its `colors.toml` is the Dawn palette
  (`background = "#faf4ed"`, `foreground = "#575279"`) — identical to what kebun hardcodes.
- **`initramfs_async=0`** (migration `1786479765`). Targets a kernel 7.1 initramfs race that breaks
  Plymouth's LUKS prompt. `nix eval` puts kebun on **6.18.40**, so it does not apply — but it will
  when nixpkgs moves to 7.1, and kebun runs exactly the Plymouth + LUKS combination affected.
- **`pkill -9` for waybar** (commit `5f3a8d45`). kebun drives waybar as a systemd user service, which
  escalates to SIGKILL on its own. Structurally immune.
- **`qmk-hid`**, **sof-firmware promotion**, **the Neovim theme symlink fix** — Framework 16 hardware,
  pacman explicit/dependency bookkeeping, and `omarchy-nvim`'s bootstrap flow respectively. None have
  a NixOS analogue.
- **Bootloader, firewall, snapshots, package installation.** systemd-boot + generations, declarative
  nftables, `/home`-only snapper, and module-options-instead-of-`install-*` remain correct NixOS
  substitutions, not gaps.
- **Script count.** 284 Omarchy commands vs 61 kebun scripts, with **zero orphans** — every script in
  `packages/scripts/default.nix` appears in `home/common.nix`. Roughly 146 of Omarchy's are Arch
  plumbing with no Nix meaning.

**Do not port** Omarchy's `cx` / `cy` shell aliases, which launch coding agents with permission
prompts disabled (`claude --permission-mode bypassPermissions`, `codex -s danger-full-access -a never`).

---

## 5. Revised parity assessment

The previous revision claimed ~85% overall and ~90% on "meaningful helpers". Checked script by
script rather than category by category, meaningful-helper parity is closer to **75-80%** — the
category-level view hid §1.2 (same names, different behaviour) and the four unwired packages in §1.1.

| Category | Assessment |
|---|---|
| Desktop shell stack | 100% vs 3.8.5 — matches component for component |
| Hardware (this ThinkPad) | ~95% — the USB-C power-profile path (§2.3) is the one hole |
| UX scripts | ~75-80% once behaviour is checked, not just names |
| App configs | ~85% — no Foot; imv/xournalpp/wiremix/Typora unconfigured |
| System features | ~85% — several unwired services (§1.1) |
| Theme system | ~20% — 1 theme, no switching, no font-set, no image wallpapers |
| **Overall (relevant features)** | **~80%** |

**Bottom line.** kebun remains a faithful port of a branch that upstream has stopped developing.
The work in §1 is small and should happen regardless of what is decided about v4 — those are
defects, not parity gaps. The v4 question (§Headline) deserves its own ADR: the honest options are
to stay on 3.8.5 indefinitely and accept it as frozen, or to plan a QuickShell + Lua migration that
rewrites the two largest modules in the repo.
