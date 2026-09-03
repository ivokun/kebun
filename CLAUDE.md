# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Kebun is a NixOS system flake for a single machine (`sakura`, a ThinkPad X13 Gen 1 with an AMD Renoir APU). It is a configuration repo, not a software project: there are no tests, no CI, and no build pipeline. Changes take effect by rebuilding the system. The desktop is kebun's port of [Omarchy](https://omarchy.org) v4 ("Quattro") to NixOS idioms — quickshell shell, Hyprland Lua config, palette-driven theming. The migration is complete (ADR-0007, stages 1–6), but the sakura deploy runtime gates are still pending: everything since Stage 2 was verified eval-only from the HTPC, never on the target machine.

## Commands

```bash
# Type-check / build without activating — the fast iteration loop.
# Catches eval errors, missing options, and build failures. Use this first.
nixos-rebuild build --flake .#sakura

# Apply the config (nh is installed by the flake and is the normal path)
nh os switch .

# Apply without nh
sudo nixos-rebuild switch --flake .#sakura

# Format every .nix file (alejandra, wired up as the flake formatter)
nix fmt

# Update flake inputs
nix flake update              # all inputs
nix flake update nixpkgs      # one input

# Emergency: /etc/nix/nix.conf ends up with broken placeholder
# trusted-public-keys after some bad rebuilds. This repairs and rebuilds.
./fix-and-rebuild.sh
```

Verifying a change is a runtime activity, not a test run. After `switch`, check
`systemctl --failed`, `systemctl --user --failed`, and `journalctl -b -p warning`. Hyprland
config changes apply on reload; UWSM/session changes need a re-login.

## Architecture

### Wiring — everything routes through `flake.nix`

`flake.nix` is the only place modules get connected, and it does the connecting **imperatively via explicit lists**. There is no auto-import of directories.

- `sharedModules` — the NixOS-level modules from `hosts/common/`.
- `mkHomeManagerModules` — the home-manager modules from `home/`.
- `mkSystem` composes: `sharedModules` ++ `./hosts/${hostname}` ++ the home-manager NixOS module ++ the per-user home modules.

**A new file under `home/features/` or `hosts/common/` does nothing until you add it to the matching list in `flake.nix`.**

Home Manager runs as a NixOS module (`home-manager.nixosModules.home-manager`), not standalone — so a single rebuild applies both system and user config, and there is no separate `home-manager switch` step.

`specialArgs`/`extraSpecialArgs` pass `inputs`, `username`, `hostname`, and `system` to every module on both layers. Modules take these as function arguments rather than referencing config paths.

### Layers

| Layer | Path | Purpose |
|---|---|---|
| NixOS, shared | `hosts/common/` | Boot, nix settings, desktop stack, networking, users, dev tools, snapshots |
| NixOS, host | `hosts/sakura/` | Hardware, LUKS/TPM2, hibernation, power profiles, NFS, Docker |
| Home, shared | `home/common.nix` | User package set (incl. custom scripts), browser flags, mime defaults |
| Home, host | `home/sakura.nix` | Monitor layout (`lib.mkForce`), borg excludes |
| Home, features | `home/features/` | One file per concern — hyprland (Lua emission), omarchy-shell, shell, terminals, webapps, … |
| Packages | `packages/` | Custom script derivations, vendored Omarchy shell environment + theme, Plymouth theme |

### Custom scripts — a two-step wiring

`packages/scripts/default.nix` is a **plain attrset of `writeShellScriptBin` derivations**, consumed with `import ../packages/scripts {inherit pkgs;}` (not `callPackage`, not a flake output). ~45 scripts live there: screenshots, battery readouts, shell menus, monitor toggles, dictation, reminders. Menu scripts sink into `omarchy-menu-select` / `omarchy-menu-input` (the shell menu's dmenu mode) and notifications go through `omarchy-notification-send` (the shell is the notification daemon) — scripts no longer talk to waybar/walker/mako directly.

Adding a script requires two edits:
1. Define it in `packages/scripts/default.nix`.
2. Add its name to the `++ (with scripts; [...])` list in `home/common.nix` — otherwise it is never installed and never reaches `PATH`.

Scripts reference their dependencies by store path (`${pkgs.grim}/bin/grim`) rather than relying on `PATH`. Follow that; the exceptions are scripts calling other kebun scripts (e.g. `launch-or-focus`), which do rely on session `PATH`. Scripts that need `hyprctl` take the compositor package as a parameter — the flake input's build, not nixpkgs' `pkgs.hyprland` (the two drift).

### Hyprland keybindings use `o.bind`

`home/features/hyprland.nix` (~700 lines) is the largest module. It emits the Hyprland Lua layer via `xdg.configFile` — `hyprland.lua` (the entry file, which loads the vendored upstream defaults from `$OMARCHY_PATH` and then kebun's overrides) plus `envs.lua`, `monitors.lua`, `input.lua`, `bindings.lua`, `windows.lua`, `looknfeel.lua`, and `autostart.lua`. Hyprland ≥0.53 auto-prefers `hyprland.lua` over `hyprland.conf`, so the HM-generated `.conf` is inert.

Bindings live in the `bindings.lua` block as `o.bind("KEYS", "description", dispatcher)` — upstream's helper layered on Hyprland 0.56's native `hl.*` API. **Descriptions are load-bearing:** SUPER+K runs `omarchy-menu-keybindings`, which renders the cheatsheet from the loaded binds (`hyprctl binds`) plus a Lua dofile of `~/.config/hypr/hyprland.lua`, so a binding declared with a nil description is invisible in the keybinding menu. Nil-description binds are for things that shouldn't be listed — workspace switching, media keys, clipboard shortcuts, mouse drags, lid switches.

Three dispatcher shapes appear in `bindings.lua`:

- **Shell verbs** — `omarchy-menu …`, `omarchy-shell …`, `omarchy-menu-keybindings`, `omarchy-notification-send`, `omarchy-system-lock`: the vendored QuickShell's IPC surface.
- **Kebun scripts** — `show-battery`, `menu-webapp`, `toggle-laptop-display`, `dictation-ptt`, …: defined in `packages/scripts/default.nix` (two-step wiring above).
- **uwsm-wrapped apps** — GUI launches keep the `uwsm app --` prefix inside the command string (`o.bind("SUPER + RETURN", "Terminal", "uwsm app -- alacritty …")`). String dispatchers are exec'd directly; nothing wraps them for you.

### Declarative web apps

`home/features/webapps.nix` derives three things from one `webapps` list: `xdg.desktopEntries`, the `menu-webapp` picker (an `omarchy-menu-select` menu), and focus-or-launch commands. Edit the list; don't hand-write desktop entries — the entries surface in the shell's app search and the app grid. `match` is the substring used to focus an existing window — Chromium `--app` mode yields app_id `chrome-<host>__-Default`, so match on the host.

### Theme — single-sourced palette, rendered at build time

Rose Pine Dawn is single-sourced in `lib/palette.nix`: upstream's 25-key `colors.toml` schema plus kebun's semantic aliases and derived forms. The shell theme is rendered at **build time** by `packages/omarchy/theme.nix` with the vendored upstream template engine (output byte-identical to the reference machine's staged shell.toml), and `home/features/omarchy-shell.nix` stages it via `home.file` to `~/.local/state/omarchy/current/theme/{colors.toml,shell.toml}` — exactly the two files the shell reads at startup (`watchChanges: false`). Retheme = edit `lib/palette.nix` + rebuild + restart the shell; multi-theme runtime switching is out of scope.

Deliberately not palette-driven: the upstream-identical literals in the Lua layer — inactive border `rgba(595959aa)`, shadow config, groupbar — stay hardcoded to match upstream byte-for-byte. Untouched palette consumers: helix, nvim, and tmux keep their own (plugin) palettes, and the GTK/Qt side in `theme-rose-pine.nix` uses packaged themes (`rose-pine-gtk-theme` etc.), not hexes.

### Shell

`fish` is the login shell (`hosts/common/users.nix`). `programs.zsh.enable` stays on at the system level for compatibility, and `home/features/shell.nix` still configures zsh alongside shared tooling (atuin, direnv, zoxide, fzf). Fish-specific abbreviations, functions, and plugins live in `home/features/fish.nix`.

## Constraints and gotchas

- **Never put `swapDevices` in `hosts/common/`.** The persistent swap device is a dedicated LUKS partition (`luks-e1906…`) declared in `hosts/sakura/hardware-configuration.nix` specifically to keep it out of shared modules. zram (50%, zstd) is primary swap; the LUKS partition is also the hibernation resume target (`boot.resumeDevice` in `hosts/sakura/default.nix`).
- **UWSM is mandatory for launched apps.** `programs.hyprland.withUWSM = true`. In the Lua layer, `o.launch`/`o.launch_on_start` wrap with `uwsm-app --`; `o.exec_on_start` is raw. The shell supervisor uses `o.exec_on_start("uwsm app -- omarchy-launch-shell")` — an explicit wrap, because upstream's `default/hypr/autostart.lua` launches the shell with a raw exec (documented divergence). A raw `exec` breaks systemd session integration (the app lands outside the session scope).
- **New omarchy verbs require two-step wiring.** Add the script to `wrappedScripts` (and its PATH deps) in `packages/omarchy/default.nix`. The vendored bin scripts are verbatim upstream files that resolve their tools from session `PATH` and silently fail without it.
- **Kebun menus sink into `omarchy-menu-select`/`omarchy-menu-input`** (the shell menu's dmenu mode), not upstream's JSONC route tree. Custom menu content via those two verbs is the pattern, not a workaround.
- **HM owns `~/.local/state/omarchy/current/theme/`** (generated output). `shell.json`, `plugins/`, and `toggles/` are user/runtime state — never HM-manage those.
- **`security.pam.services."omarchy-lock-password"` is load-bearing** (`hosts/common/desktop.nix`): the shell's lock plugin refuses to lock without it.
- **Deploy pending: Stage 3+4 runtime gates never exercised.** Verification on this machine is eval-only. The first sakura deploy must check, at minimum: the shell renders, PAM unlock works, the idle plugin screensaver/lock timings fire, the ADR-0004 lock guard and ADR-0006 suspend path revalidate, and SUPER+K lists the expected binds. Note v3's 900s idle-suspend was **not** carried (idle is the shell plugin: 150s screensaver / 300s lock from shell.json).
- **Deno override.** `flake.nix` carries an overlay skipping the flaky Deno test `uv_compat::tests::tty_reset_mode_restores_termios`. Verify the test actually passes before dropping it.
- **State versions are pinned at `25.05`** (`system.stateVersion` in core.nix and sakura/default.nix, `home.stateVersion` in home/common.nix). Don't bump without reading upstream migration notes.
- **Home Manager backup extension is `hm-backup`.** Pre-existing dotfiles get renamed on first activation rather than causing a failure.
- **systemd ordering with `power-profiles-daemon`.** `power-profile-auto` is `wantedBy` the daemon service, not `multi-user.target` — targets are implicitly ordered after everything they `Want`, so target-binding plus `after = ppd` creates a cycle and `switch-to-configuration` aborts with status 4. See the comment in `hosts/sakura/default.nix`.
- **iwd, not NetworkManager.** `networkmanager.enable = false` is deliberate — `impala` (the WiFi TUI) drives iwd's D-Bus API directly and the two conflict. Wired/DHCP goes through systemd-networkd.
- **Out-of-store-managed config trees.** Neovim (`home/nvim` → `~/.config/nvim`) and opencode (`home/opencode` → `~/.config/opencode`) are copied file-by-file via `home.file`/`xdg.configFile` because LazyVim manages its own plugins. `home/features/opencode.nix` enumerates every file explicitly — new prompts/skills must be added there.
- **`/home/.snapshots` must be created manually** as a btrfs subvolume before snapper works: `sudo btrfs subvolume create /home/.snapshots`. The tmpfiles rule only fixes permissions.
- **This repo is edited and built on IVOKUN-HTPC, not on kebun's target.** Hostname `ivokun-htpc`, an Arch + Omarchy 4.0.2 desktop (B550M board, live reference at `/usr/share/omarchy`). It is not kebun-managed; kebun deploys to `sakura` only. The HTPC's `~/.config` is Omarchy's own state — useful as a reference, never kebun-managed. Don't treat HTPC hardware or its monitor layout as sakura facts.

## Conventions

Commits follow Conventional Commits with a scope naming the subsystem: `fix(hyprland):`, `feat(omarchy):`, `chore(flake):`, `docs(adr):`. Run `nix fmt` before committing.

Architecture decisions get an ADR in `docs/adr/` (see `template.md`).

## Docs

- `INSTALL.md` — full install guide (LUKS + BTRFS + flakes)
- `OMARCHY_DISCREPANCY_REPORT.md` — historical port-time audit (2026-09-01) that fed ADR-0007; still a useful v4 architecture reference, no longer status
- `docs/omarchy/quattro-port-inventory.md` — historical port-time inventory (same caveat)
- `docs/omarchy-parity-backlog.md` — follow-ups, re-scoped post-migration (see its addendum)
- `docs/adr/` — architecture decision records
- `docs/omarchy/` — research briefs on upstream Omarchy
- `thoughts/` — in-progress plans and drafts (not authoritative)

`AGENTS.md` is a symlink to this file — edit `CLAUDE.md` only.
