# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Kebun is a NixOS system flake for a single machine (`sakura`, a ThinkPad X13 Gen 1 with an AMD Renoir APU). It is a configuration repo, not a software project: there are no tests, no CI, and no build pipeline. Changes take effect by rebuilding the system. The desktop is a port of [Omarchy](https://omarchy.org) (an Arch/Hyprland distro) to NixOS idioms, tracking Omarchy's v3.8.x stable line.

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
| Home, features | `home/features/` | One file per concern — hyprland, waybar, shell, terminals, theme, … |
| Packages | `packages/` | Custom script derivations, Plymouth theme |

### Custom scripts — a two-step wiring

`packages/scripts/default.nix` is a **plain attrset of `writeShellScriptBin` derivations**, consumed with `import ../packages/scripts {inherit pkgs;}` (not `callPackage`, not a flake output). ~70 scripts live there: screenshots, battery readouts, walker-driven menus, monitor toggles, dictation, reminders.

Adding a script requires two edits:
1. Define it in `packages/scripts/default.nix`.
2. Add its name to the `++ (with scripts; [...])` list in `home/common.nix` — otherwise it is never installed and never reaches `PATH`.

Scripts reference their dependencies by store path (`${pkgs.grim}/bin/grim`) rather than relying on `PATH`. Follow that; the exceptions are scripts calling other kebun scripts (e.g. `launch-or-focus`), which do rely on session `PATH`.

### Hyprland keybindings must use `bindd`

`home/features/hyprland.nix` (~700 lines) is the largest module and holds bindings, window rules, hypridle, hyprlock, hyprsunset, mako, and the SwayOSD stylesheet.

Bindings go in the `bindd` list — the variant with a description field. The `menu-keybindings` script (SUPER+K) builds its cheatsheet from `hyprctl -j binds | jq 'select(.description != "")'`, so **a binding declared with plain `bind` is invisible in the keybinding menu**. Plain `bind`/`bindr`/`bindl`/`bindm` are reserved for things that shouldn't be listed (workspace switching, media keys, mouse drags).

### Declarative web apps

`home/features/webapps.nix` derives three things from one `webapps` list: `xdg.desktopEntries`, the `menu-webapp` walker picker, and focus-or-launch commands. Edit the list; don't hand-write desktop entries. `match` is the substring used to focus an existing window — Chromium `--app` mode yields app_id `chrome-<host>__-Default`, so match on the host.

### Theme is hardcoded, and duplicated

Rose Pine Dawn is not driven by a shared palette module. Colors are re-declared per-file across `home/features/{theme-rose-pine,hyprland,waybar,terminals,ghostty,kitty,btop,helix,starship,fastfetch,mpv,editors}.nix`, `home/nvim/lua/`, and `packages/scripts/default.nix`. A theme change means editing all of them plus a rebuild. `theme-rose-pine.nix` holds the GTK/Qt/cursor side and a palette attrset used only within that file.

### Shell

`fish` is the login shell (`hosts/common/users.nix`). `programs.zsh.enable` stays on at the system level for compatibility, and `home/features/shell.nix` still configures zsh alongside shared tooling (atuin, direnv, zoxide, fzf). Fish-specific abbreviations, functions, and plugins live in `home/features/fish.nix`.

## Constraints and gotchas

- **Never put `swapDevices` in `hosts/common/`.** The persistent swap device is a dedicated LUKS partition (`luks-e1906…`) declared in `hosts/sakura/hardware-configuration.nix` specifically to keep it out of shared modules. zram (50%, zstd) is primary swap; the LUKS partition is also the hibernation resume target (`boot.resumeDevice` in `hosts/sakura/default.nix`).
- **UWSM is mandatory for launched apps.** `programs.hyprland.withUWSM = true`, so every `exec` binding and `exec-once` entry wraps the command as `uwsm app -- <cmd>`. A raw `exec` breaks systemd session integration (the app lands outside the session scope).
- **Walker needs elephant.** Walker 2.x is only a frontend; `services.elephant.enable = true` in `hosts/common/desktop.nix` provides every provider. Both come from nixpkgs as a co-maintained pair — do not re-add them as flake inputs (walker's own module collides with the nixpkgs `services.elephant`). Walker's config must be at `environment.etc."xdg/walker/config.toml"`; `/etc/walker` is not on `XDG_CONFIG_DIRS` and gets silently ignored.
- **Waybar is a systemd user service.** Use the `toggle-waybar` / `restart-waybar` scripts, not `pkill waybar`.
- **Deno override.** `flake.nix` carries an overlay skipping the flaky Deno test `uv_compat::tests::tty_reset_mode_restores_termios`. Verify the test actually passes before dropping it.
- **State versions are pinned at `25.05`** (`system.stateVersion` in core.nix and sakura/default.nix, `home.stateVersion` in home/common.nix). Don't bump without reading upstream migration notes.
- **Home Manager backup extension is `hm-backup`.** Pre-existing dotfiles get renamed on first activation rather than causing a failure.
- **systemd ordering with `power-profiles-daemon`.** `power-profile-auto` is `wantedBy` the daemon service, not `multi-user.target` — targets are implicitly ordered after everything they `Want`, so target-binding plus `after = ppd` creates a cycle and `switch-to-configuration` aborts with status 4. See the comment in `hosts/sakura/default.nix`.
- **iwd, not NetworkManager.** `networkmanager.enable = false` is deliberate — `impala` (the WiFi TUI) drives iwd's D-Bus API directly and the two conflict. Wired/DHCP goes through systemd-networkd.
- **Out-of-store-managed config trees.** Neovim (`home/nvim` → `~/.config/nvim`) and opencode (`home/opencode` → `~/.config/opencode`) are copied file-by-file via `home.file`/`xdg.configFile` because LazyVim manages its own plugins. `home/features/opencode.nix` enumerates every file explicitly — new prompts/skills must be added there.
- **`/home/.snapshots` must be created manually** as a btrfs subvolume before snapper works: `sudo btrfs subvolume create /home/.snapshots`. The tmpfiles rule only fixes permissions.

## Conventions

Commits follow Conventional Commits with a scope naming the subsystem: `fix(hyprland):`, `feat(walker):`, `chore(flake):`, `docs(adr):`. Run `nix fmt` before committing.

Architecture decisions get an ADR in `docs/adr/` (see `template.md`).

## Docs

- `INSTALL.md` — full install guide (LUKS + BTRFS + flakes)
- `OMARCHY_DISCREPANCY_REPORT.md` — parity analysis vs Omarchy, incl. the v3.8 vs v4 (Quickshell/Lua) fork and what tracking each would mean
- `docs/adr/` — architecture decision records
- `docs/omarchy/` — research briefs on upstream Omarchy
- `thoughts/` — in-progress plans and drafts (not authoritative)

`AGENTS.md` is a symlink to this file — edit `CLAUDE.md` only.
