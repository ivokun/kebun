# Omarchy Parity Backlog

Actionable follow-ups from the 2026-08-27 audit in `OMARCHY_DISCREPANCY_REPORT.md`.
Each item names the file to touch and what the change is, so none of them
require re-deriving the analysis.

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

## 1. Decide first — these gate other work

### 1.1 Omarchy 4 / Quattro — **blocked on ADR-0007**

See `docs/adr/0007-stay-on-omarchy-3-8-or-migrate-to-quattro.md`. Everything
below assumes the 3.8.x-shaped stack survives. If Quattro is chosen, items 3.x
and most of 4.x become moot.

### 1.2 Hyprland version skew — **blocked on a choice**

The compositor is `0.54.0` (the pinned `hyprland` flake input, frozen since
2026-04-30), but all ~60 `hyprctl` call sites in `packages/scripts/default.nix`
use `${pkgs.hyprland}/bin/hyprctl`, which resolves to nixpkgs' **`0.56.0`**.
Verify with:

```bash
nix eval --raw .#nixosConfigurations.sakura.config.programs.hyprland.package.version
nix eval --raw .#nixosConfigurations.sakura.pkgs.hyprland.version
```

Two ways out:

- **Point the scripts at the compositor's own package.** Bind
  `hyprland = config.programs.hyprland.package` (or the flake input) once in
  `packages/scripts/default.nix` and substitute it for `pkgs.hyprland`
  throughout. Keeps 0.54.0, removes the skew, no behaviour change.
- **Bump the input to 0.56+ and standardise there.** This is the larger change
  and it is *coupled* to item 2.1 below — do not do one without the other.

Whichever is picked, do it before bumping Hyprland for any other reason.

---

## 2. Coupled to a Hyprland 0.56 bump — do NOT apply in isolation

### 2.1 Opacity retune

Omarchy commit `bfab1a70` raised every opacity value because Hyprland 0.56
fixed an alpha-premultiplication bug that made old values render more
transparent than intended. kebun's current values are **correct for 0.54** and
must move only when the compositor does:

| `home/features/hyprland.nix` | now | on 0.56+ |
|---|---|---|
| line 199 (catch-all) | `0.97 0.9` | `0.985 0.96` |
| lines 212-213 (browsers) | `1 0.97` | `1.0 0.985` |

### 2.2 `menu-keybindings` JSON fragility

`packages/scripts/default.nix:510` uses `hyprctl -j binds | jq` under
`set -euo pipefail`, so malformed JSON aborts with no menu at all. Hyprland
0.56.0/0.56.1 emitted invalid JSON here; upstream rewrote the parser to read
plain-text `hyprctl binds` (commit `05d6f489`).

**Tested on Hyprland 0.56.2: the JSON parses fine** (180 binds, 178 with
descriptions), so this is not urgent. Only relevant if the bump lands on
exactly 0.56.0 or 0.56.1. A `|| true` fallback with a static hint would make
the script fail soft regardless.

---

## 3. Host config drift

### 3.1 Monitor layout is stale — **blocked on confirming your displays**

`home/sakura.nix:11-15` declares an `HDMI-A-1` display that isn't in use and
omits `DP-1` entirely:

```nix
",preferred,auto,1"
"HDMI-A-1,1920x1080@60.00,2272x1440,1.00"
"DP-2,3840x2160@60.00,1920x0,1.5"
```

The live Arch setup (`~/.config/hypr/hyprland.conf`) is:

```
monitor=DP-1,2560x1440@59.95,1920x1440,1.00
monitor=DP-2,3840x2160@60.00,1920x0,1.50,bitdepth,10,vrr,2
```

Note kebun's `DP-2` also drops `bitdepth,10` and `vrr,2`. Confirm which
displays are actually attached before editing — this is host-specific and I
did not want to guess.

### 3.2 Fingerprint unlock

`home/features/hyprland.nix:660` has `fingerprint.enabled = false`, and the
comment above it explains why: `services.fprintd` is not enabled anywhere, so
hyprlock was probing a nonexistent D-Bus name on every unlock. Enabling it is
three steps, not a flag flip:

1. `services.fprintd.enable = true;` in `hosts/sakura/default.nix`
2. Rebuild, then `fprintd-enroll`
3. Flip `fingerprint.enabled = true`

The X13 Gen 1's Synaptics `06cb:00bd` may additionally need `libfprint-tod`.

### 3.3 Renamed NixOS options (warnings on every eval)

Not urgent, but the build is noisy. All in `hosts/`:

- `services.logind.{lidSwitch,lidSwitchDocked,lidSwitchExternalPower,powerKey,powerKeyLongPress}`
  → `services.logind.settings.Login.Handle*`
- `services.resolved.{dnssec,fallbackDns}` → `services.resolved.settings.Resolve.{DNSSEC,FallbackDNS}`
- `home.pointerCursor` now wants an explicit `enable = true`
- fzf/atuin both claim Ctrl-R; pick one (`programs.atuin.flags = ["--disable-ctrl-r"]`
  or `programs.fzf.historyWidget.command = ""`)

---

## 4. Missing features, ranked by value on this laptop

1. **Real timed reminders.** `reminder-set`/`show`/`clear` currently append to
   `$XDG_DATA_HOME/kebun-reminders.txt` and never fire. Replace with
   `systemd-run --user --on-active=<N>m`, and make `show` read
   `systemctl --user list-timers` and `clear` cancel them. Three keybindings
   already point at these names.
2. **Wi-Fi power-save toggle.** Iterate `/sys/class/net/*/wireless`, call
   `iw dev $iface set power_save on|off`. Directly relevant to battery, and
   iwd is already the stack here.
3. **Touchpad toggle.** Persist `hyprctl keyword device[...]:enabled` state and
   show an OSD. Useful when docked with an external mouse.
4. **Suspend-inhibit ("caffeine") toggle.** No current way to hold off suspend
   for a long build without editing hypridle and rebuilding.
5. **Wallpaper images.** `menu-background` offers four solid colors and
   `swaybg -c '#faf4ed' -m solid_color`; there is no image support at all, and
   `home/sakura.nix:107` still has the wiring commented out. This is a
   self-contained slice of the theming gap that does not require building
   multi-theme switching first.
6. **`ALT+TAB` doesn't raise.** Omarchy binds `bringactivetotop` as a second
   bind on the same key alongside `cyclenext`. `home/features/hyprland.nix:346-347`
   binds only `cyclenext`.
7. **Missing window rules.** No picture-in-picture handling at all
   (float/pin/size/aspect); 1Password has no `no_screen_share` rule; the
   terminal tag matches only `Alacritty` where Omarchy matches all four
   emulators.
8. **Richer share and capture.** `localsend-share` only opens the GUI —
   upstream picks a file/folder/clipboard via fzf and sends headless.
   `screenrecord` captures silent video only — upstream supports desktop
   audio, microphone, and webcam.
9. **Shell ergonomics.** No `..`/`...`/`....`; no `MANPAGER` piping man pages
   through `bat`; no SSH port-forward helpers; no tmux dev-layout builders
   (`tdl`/`tdlm`/`tsl`), which given how much agent work happens on this
   machine is probably the most useful of the group.
10. **Upstream config improvements your live `~/.config` also missed.** Because
    you customised these files, Omarchy's updater left them alone, so kebun
    inherited the older values: waybar's `custom/idle-indicator` and
    `custom/notification-silencing-indicator` modules and the
    `#custom-weather.unavailable` collapse styling; ghostty's
    `window-theme = ghostty`, `gtk-toolbar-style = flat`, `async-backend = epoll`,
    and `shell-integration-features = ssh-env` (this last one is what makes
    terminfo work over SSH); kitty's `cursor_blink_interval 0` and
    `shell_integration no-cursor`.

---

## 5. System tuning worth considering

- `net.ipv4.tcp_mtu_probing=1` — Omarchy's SSH-flakiness fix
- `usbcore.autosuspend=-1` — prevents USB peripheral dropouts
- `gtk-enable-primary-paste=true` — middle-click paste in GTK apps
- `DefaultTimeoutStopSec=5s` — caps shutdown stall (systemd default is 90s)
- Mask `systemd-networkd-wait-online.service` — avoids boot hang with no link
- `MulticastDNS=no` in resolved — kebun currently runs resolved **and**
  avahi with `nssmdns4`, both answering mDNS
- **`system-sleep/unmount-fuse` hook** *(unverified)* — lazy-unmount
  `fuse.gvfsd-fuse` before sleep, restart `gvfs-daemon` after. kebun runs
  Nautilus + gvfs and has documented suspend/resume fragility (ADR-0006,
  `hosts/common/core.nix:29-39`). Plausible contributor; test before assuming
  it's unrelated.
- Waybar indicators poll every 2s with `exec-if` where upstream pushes via
  `"signal": N` + `pkill -RTMIN+N waybar`. Functionally equivalent, but it is
  three `pgrep`/`makoctl` invocations every two seconds, forever.

---

## 6. Explicitly not doing

- **`initramfs_async=0`** (upstream migration `1786479765`). Fixes a kernel 7.1
  race that breaks Plymouth's LUKS prompt. `nix eval` puts kebun on **6.18.40**,
  so it does not apply — but revisit when nixpkgs moves to 7.1, because kebun
  runs exactly the affected Plymouth + LUKS combination.
- **`pkill -9` for waybar** (upstream `5f3a8d45`). kebun drives waybar as a
  systemd user service, which escalates to SIGKILL on its own.
- **`qmk-hid`**, sof-firmware promotion, the Neovim theme symlink fix —
  Framework 16 hardware, pacman bookkeeping, and `omarchy-nvim`'s bootstrap
  flow. No NixOS analogue.
- **Omarchy's `cx` / `cy` shell aliases**, which launch coding agents with
  permission prompts disabled (`claude --permission-mode bypassPermissions`,
  `codex -s danger-full-access -a never`).
- **App-launcher keybindings.** Upstream's stock template moved these to
  `SUPER SHIFT+*`; your live config uses plain `SUPER+B/N/D/O` and kebun
  matches you. Deliberate, not drift.
- Bootloader, firewall mechanism, root snapshots, and `install-*` scripts —
  systemd-boot + generations, declarative nftables, `/home`-only snapper, and
  module options remain correct NixOS substitutions.
