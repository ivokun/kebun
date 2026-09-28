# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Kebun is a NixOS system flake for two machines, one user (`ivokun`): `sakura`, a ThinkPad X13 Gen 1 laptop (AMD Renoir APU, live since 2026-09-04), and `ume`, an ASRock B550M-ITX/ac desktop (Ryzen 9 5900X, RX 9060 XT) — the former editing machine ivokun-htpc's hardware, currently **pre-install** (see `INSTALL-UME.md`; its `hosts/ume/hardware-configuration.nix` is a snapshot of the *current* disk layout, to be regenerated after install). It is a configuration repo, not a software project: there are no tests, no CI, and no build pipeline. Changes take effect by rebuilding the matching host. The desktop is kebun's port of [Omarchy](https://omarchy.org) v4 ("Quattro") to NixOS idioms — quickshell shell, Hyprland Lua config, palette-driven theming. The migration is complete (ADR-0007, stages 1–6) and deployed on sakura; first-deploy fixes plus the auth/greeter overhaul are in ADR-0009–0011, and the multi-host modeling is ADR-0017.

## Commands

```bash
# On the matching host: type-check/build without activating — the fast loop.
nixos-rebuild build --flake .#sakura   # on sakura
nixos-rebuild build --flake .#ume      # on ume (post-install only)

# On another machine with Nix: build either host's closure directly.
# nixos-rebuild is not installed on the Arch reference host.
nix build .#nixosConfigurations.sakura.config.system.build.toplevel
nix build .#nixosConfigurations.ume.config.system.build.toplevel

# Apply the config — run ON the matching host (sakura switches sakura,
# ume switches ume; never build-then-switch cross-host). nh is installed
# from nixpkgs by home/common.nix and is the normal path.
nh os switch .

# Apply without nh — still on the matching host
sudo nixos-rebuild switch --flake .#sakura   # or .#ume

# Format every .nix file (alejandra, wired up as the flake formatter)
nix fmt

# Update a flake input deliberately; avoid blanket updates during installation.
nix flake update nixpkgs

# Emergency: /etc/nix/nix.conf ends up with broken placeholder
# trusted-public-keys after some bad rebuilds. This repairs and rebuilds,
# choosing the local (managed) hostname — refuses to run off sakura/ume;
# test its repair expressions anywhere:
./fix-and-rebuild.sh --self-test
./fix-and-rebuild.sh
```

Verifying a change is a runtime activity, not a test run. After `switch`, check
`systemctl --failed`, `systemctl --user --failed`, and `journalctl -b -p warning`. Hyprland
config changes apply on reload; UWSM/session changes need a re-login.

## Architecture

**Migrated to [Den](https://github.com/denful/den) (ADR-0013, 2026-09-13): the
wiring is now declarative, aspect-oriented, entity-as-data.** Visual map:
the auto-generated mermaid graphs at the bottom of `README.md` (Overview /
Hosts / Home Manager / Dependencies). Regenerate with
`nix run .#update-readme`; raw `.mmd` via `nix build .#diagrams-mermaid`;
plain-text pipeline summary for LLMs via `nix run .#graph`.

The graph: two NixOS hosts — `host:sakura` and `host:ume` — each with a
nested `user:ivokun` (homeManager). The host aspects (`host-base`, `core`,
`desktop`, `dev`, `networking`, `printing`, `snapper`, `shell-entry`, and
`hostname`) mount via `includes`; the glue that bridges the two scopes is
`host-to-users` (policy resolve), `hm-user-detect` (battery), and
`os-to-host` (os-class forward). Host variance flows through the typed
`kebun.host` capability options (below), not through hostname matching.

### Wiring — entities declared as data in `modules/`

`flake.nix` is a Den entrypoint (`inputs.den.flakeModule` + `evalModules
./modules/`). All wiring is declarative now:

- `modules/den.nix` — Den flake-module entrypoint and formatter.
- `modules/aspects.nix` — host aspects (`core`, `desktop`, `dev`,
  `networking`, `printing`, `snapper`, `shell-entry` from
  `modules/aspects/*.nix`), the reusable `host-base` aspect (hostname
  battery, `_module.args.inputs`, HM defaults, the shared overlays, and the
  `kebun.host` capability options), the `sakura`/`ume` host aspects
  composing them + importing `hosts/<name>/`, entity declarations, schema
  defaults and stateVersions.
- `modules/users.nix` — the `ivokun` user aspect: the `users.users.ivokun`
  block via context args, includes `den.batteries.define-user` (no
  `primary-user` battery — it would pull in NetworkManager groups, and this
  host deliberately runs iwd), and imports all `home/**` modules untouched
  (their `username`/`system`/`inputs` fn args are supplied via `_module.args`
  on the homeManager class — the battery reserves
  `home-manager.extraSpecialArgs`).
- `modules/diagrams-mermaid.nix` — mermaid graph generation into
  README (`nix run .#update-readme`).

**A new file under `home/features/` or `modules/aspects/` still does nothing
until imported** — the lists live in `modules/users.nix` (home) /
`modules/aspects.nix` (host) instead of `flake.nix`.

Home Manager runs nested under the host (`home-manager` battery with
`den.batteries.home-manager`), so one rebuild applies both system and user
config. Modules receive `username`/`system`/`inputs` as fn args via
`_module.args` (not `specialArgs` anymore).

### Hosts — shared base, host-owned hardware (ADR-0017)

| Host | Machine | Class | Hardware files | Status |
|---|---|---|---|---|
| sakura | ThinkPad X13 Gen 1 (AMD Renoir) | laptop | `hosts/sakura/` | live since 2026-09-04 |
| ume | ASRock B550M-ITX/ac (Ryzen 9 5900X, RX 9060 XT) | desktop | `hosts/ume/` | pre-install (runbook: `INSTALL-UME.md`) |

Every host aspect includes the reusable `host-base` aspect
(`modules/aspects.nix`): hostname battery, `_module.args.inputs`, nested-HM
defaults, the shared overlays, and the typed **`kebun.host` capability
options** (`isLaptop`, `greeterLayout`, `monitorsLua`). Hosts set them in
`hosts/<name>/default.nix`; Home Manager branches on them via `osConfig`
(e.g. `osConfig.kebun.host.isLaptop or false` in `home/common.nix` and
`home/features/hyprland.nix`) — **never do hostname conditionals in HM**
(`hostName`-matching is the anti-pattern this replaces; a new host
declaration, not a home-module edit, is how variance is added).

Shared workstation policy (Docker, NFS `/mnt/tubeinas`, snapper, desktop
stack) lives in `modules/aspects/*.nix` and is applied to both hosts;
machine facts (hardware-config, LUKS/TPM2, GPU/Bluetooth, kernel modules,
power-key behavior) live in `hosts/<name>/`. Note `hosts/ume/hardware-configuration.nix`
is a **pre-install snapshot** of the current disk layout — regenerate it
after install repartitions anything, and see `INSTALL-UME.md` before
touching that machine's disk at all.

## Layers

| Layer | Path | Purpose |
|---|---|---|
| Den entry | `modules/den.nix` | Den flake module and formatter |
| Entities/shared host base | `modules/aspects.nix` | Host/user declarations, defaults, hostname, `_module.args`, HM defaults, overlays, `kebun.host` capability options |
| NixOS aspects | `modules/aspects/*.nix` | Shared workstation policy: boot, nix settings, desktop stack, networking, dev tools, snapshots (per-concern aspect files) |
| NixOS host | `hosts/sakura/`, `hosts/ume/` | Machine facts only: hardware, LUKS/TPM2, GPU, kernel modules, monitors/greeter layout |
| Home, shared | `home/common.nix` | User package set (incl. custom scripts), browser flags, mime defaults |
| Home, host | `home/backup.nix` | Shared Borg backup excludes |
| Home, features | `home/features/*` | One file per concern — hyprland (Lua emission), omarchy-shell, shell, terminals, webapps, … |
| User aspect | `modules/users.nix` | Wires the home modules into `den.aspects.ivokun` |
| Diagrams | `modules/diagrams-mermaid.nix` | mermaid graph generation into README (den-diagram; regen: `nix run .#update-readme`) |
| Packages | `packages/` | Custom script derivations, vendored Omarchy shell environment + theme, IVOKUN wordmark, Plymouth theme |

### Custom scripts — a two-step wiring

`packages/scripts/default.nix` is a **plain attrset of `writeShellScriptBin` derivations**, consumed with `import ../packages/scripts {inherit pkgs;}` (not `callPackage`, not a flake output). ~45 scripts live there: screenshots, battery readouts, shell menus, monitor toggles, dictation, reminders. Menu scripts sink into `omarchy-menu-select` / `omarchy-menu-input` (the shell menu's dmenu mode) and notifications go through `omarchy-notification-send` (the shell is the notification daemon) — scripts no longer talk to waybar/walker/mako directly.

Adding a script requires two edits:
1. Define it in `packages/scripts/default.nix`.
2. Add its name to the `++ (with scripts; [...])` list in `home/common.nix` — otherwise it is never installed and never reaches `PATH`.

Laptop-only scripts additionally need matching `lib.optionals laptop` gates
in `home/common.nix` (installation) and `home/features/hyprland.nix`
(bindings/verbs); keep those gates in sync.

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

The same palette drives the greeter and the boot splash at build time (ADR-0011): the SDDM greeter is the vendored upstream theme re-skinned in `modules/aspects/desktop.nix` (hex substitutions + channel-wise PNG recolor that preserves alpha), and both the greeter and Plymouth show the shared IVOKUN wordmark (`packages/ivokun-wordmark`). A palette edit therefore rethemes shell, greeter and boot in one rebuild.

Deliberately not palette-driven: the upstream-identical literals in the Lua layer — inactive border `rgba(595959aa)`, shadow config, groupbar — stay hardcoded to match upstream byte-for-byte. Untouched palette consumers: helix, nvim, and tmux keep their own (plugin) palettes, and the GTK/Qt side in `theme-rose-pine.nix` uses packaged themes (`rose-pine-gtk-theme` etc.), not hexes.

### Shell

`fish` is the login shell (wired via `modules/users.nix`, formerly
`hosts/common/users.nix`). `programs.zsh.enable` stays on at the system level
for compatibility, and `home/features/shell.nix` still configures zsh
alongside shared tooling (atuin, direnv, zoxide, fzf). Fish-specific
abbreviations, functions, and plugins live in `home/features/fish.nix`.

## Constraints and gotchas

- **`modules/aspects/` files are plain NixOS modules, not aspect bodies.** The `username`/`hostname` fn args they historically took are gone; anything new should use context args (`{ host, user, pkgs, ... }`) or `_module.args`.
- **Never put `swapDevices` in `modules/aspects/` (ex-"hosts/common").** Swap is hardware-specific: sakura's dedicated LUKS partition is only 8.8 GiB against 30.6 GiB RAM; ume's pre-install snapshot records a Btrfs swapfile without a verified resume offset. Both have hibernation disabled (`boot.resumeDevice` unset); zram (50%, zstd) is the shared primary swap.
- **UWSM is mandatory for launched apps.** `programs.hyprland.withUWSM = true`. In the Lua layer, `o.launch`/`o.launch_on_start` wrap with `uwsm-app --`; `o.exec_on_start` is raw. The shell supervisor uses `o.exec_on_start("uwsm app -- omarchy-launch-shell")` — an explicit wrap, because upstream's `default/hypr/autostart.lua` launches the shell with a raw exec (documented divergence). A raw `exec` breaks systemd session integration (the app lands outside the session scope).
- **Vendored omarchy scripts are verbatim upstream, patched at build time.** Upstream's Arch shebangs (`#!/bin/bash`, `#!/usr/bin/python3`) don't exist on NixOS — `packages/omarchy/default.nix` rewrites them tree-wide **before** `wrapProgram` (wrapProgram relocates originals verbatim to `.name-wrapped`, so a broken shebang there survives the wrap). New verbs still need two-step wiring: add to `wrappedScripts` + PATH deps in `packages/omarchy/default.nix`; a new interpreter kind needs a new rewrite rule (ADR-0009).
- **Kebun menus sink into `omarchy-menu-select`/`omarchy-menu-input`** (the shell menu's dmenu mode), not upstream's JSONC route tree. Custom menu content via those two verbs is the pattern, not a workaround.
- **HM owns `~/.local/state/omarchy/current/theme/`** (generated output). `shell.json`, `plugins/`, and `toggles/` are user/runtime state — never HM-manage those.
- **`security.pam.services."omarchy-lock-password"` is load-bearing** (`modules/aspects/desktop.nix`): the shell's lock plugin refuses to lock without it.
- **Editing machines vs. build targets.** The repo is currently edited on **ivokun-htpc** (Arch, not kebun-managed). There are two targets: **sakura** (live since 2026-09-04) and **ume** (pre-install — runbook `INSTALL-UME.md`; its target hardware *is* ivokun-htpc, so nothing about that machine is activated until the gated install there runs). Never build-then-switch wherever you happen to be editing: build either host's closure remotely (`nix build .#nixosConfigurations.<host>.config.system.build.toplevel`); activation happens only on the matching target (`nh os switch .` from that machine's checkout, or `sudo nixos-rebuild switch --flake .#<host>`).
- **Machine facts vs. editing-machine facts.** ivokun-htpc's disk facts now feed `hosts/ume/hardware-configuration.nix` — but as a **pre-install snapshot**, to be regenerated after install (see `INSTALL-UME.md`). Its runtime quirks (failed Borg user service, failed `/mnt/tubeinas` mount) are not kebun state; its Arch `~/.config` is Omarchy's own, useful for upstream comparison only. Don't treat ivokun-htpc quirks as sakura facts.
- **Deploy status: live since 2026-09-04.** The Stage 3+4 gates were exercised on sakura (shell renders, PAM unlock, SUPER+K cheatsheet, idle/lock timings). Post-deploy hardening landed as ADR-0009–0012. Known accepted gaps: the network panel's connection state now derives from the `omarchy-network-status` script via a build-time patch (ADR-0012 — Quickshell's Networking is NM-only), while panel-side Wi-Fi scan/connect/forget still need NM (Wi-Fi management: the panel's impala button, SUPER+CTRL+W, or iwctl), there is no idle system suspend (idle is the shell plugin: 150s screensaver / 300s lock from shell.json — v3's 900s idle-suspend was **not** carried), there is no hibernation (see the swap bullet above), and fingerprint unlock stays deferred (backlog §3.2). Pre-suspend locking lives in `home/features/sleep-lock.nix`: a UWSM user service holds a `PrepareForSleep` delay inhibitor (15s window in `modules/aspects/desktop.nix`) so the shell locks before lid- or menu-triggered suspend. The real session is SDDM → UWSM-managed Hyprland.
- **Sakura boot has zero prompts by design (ADR-0010).** Its two LUKS volumes auto-unlock via TPM2 at PCR 7; SDDM's password unlocks the keyring. Ume requests the same mechanism for its root container, but remains pre-install: do not claim zero-prompt boot until enrollment and fallback are tested per `INSTALL-UME.md`. If firmware policy shifts PCR 7, boot falls back to the passphrase prompt. Autologin stays off. PCR 7 enrollment is convenience, not verified boot; Secure Boot signing is not provisioned.
- **Don't hand-edit HM-managed paths.** Foreign files in HM-owned locations break activation: regular files get moved to `.hm-backup`, but a symlink to a non-store target (e.g. a hand-made `bindings.lua` stopgap) aborts with "would be clobbered" and the whole `nh os switch` fails until the stopgap is removed.
- **Package overrides.** `modules/aspects.nix` carries the Deno flaky-test skip and the shared OpenCode overlay. OpenCode V2 2.0.18 is packaged in `packages/opencode/opencode-v2.nix`; `lib/opencode-overlay.nix` must remain applied to both the host and nested Home Manager package sets or HM silently falls back to nixpkgs' V1 package. The managed config/plugins use V2 APIs (`agents`, ordered `permissions`, `request.body`, and `setup(ctx)`), and the wrapper blocks self-updates. A version bump requires source/dependency hash updates plus resolved-config, plugin, selected-model, MCP, and native-watcher smoke tests (ADR-0016), not just a new source hash. ADR-0015 also backports sequential-thinking 2026.8.31 and GitHub MCP 1.12.2 under `packages/opencode/`; retain them until the pinned nixpkgs equivalents are at least those versions. Verify the skipped Deno test before dropping its override.
- **State versions are pinned at `25.05`** (Den defaults, both host modules, and `home/common.nix`). Don't bump without reading upstream migration notes.
- **Home Manager backup extension is `hm-backup`.** Pre-existing dotfiles get renamed on first activation rather than causing a failure.
- **systemd ordering with `power-profiles-daemon`.** `power-profile-auto` is `wantedBy` the daemon service, not `multi-user.target` — targets are implicitly ordered after everything they `Want`, so target-binding plus `after = ppd` creates a cycle and `switch-to-configuration` aborts with status 4. See the comment in `hosts/sakura/default.nix`.
- **iwd, not NetworkManager.** `networkmanager.enable = false` is deliberate — `impala` (the WiFi TUI) drives iwd's D-Bus API directly and the two conflict. Wired/DHCP goes through systemd-networkd.
- **Explicitly managed config trees.** Neovim (`home/nvim` → `~/.config/nvim`) is copied file-by-file because LazyVim manages its own plugins. OpenCode's readable source lives under `home/opencode`; `home/features/opencode.nix` renders the main JSON with store-path MCP commands and enumerates prompts, skills, and plugins explicitly. New prompts/skills must be added there, and generated/runtime state (`node_modules`, locks, credentials, service files) must not be Home Manager-owned.
- **Snapper needs a Btrfs subvolume at `/home/.snapshots`.** `home-snapshots-subvolume.service` creates it and safely replaces only the empty regular directory left by the old tmpfiles rule. Do not replace a non-empty path automatically; inspect it first. After deployment verify with `sudo btrfs subvolume show /home/.snapshots` before trusting snapshots.
- **Backups are not automated.** `home/backup.nix` only writes exclusions for manual Borg runs; Snapper is same-disk history, not an off-host backup. A scheduled job still needs an explicit repository and secret-management decision.

## Conventions

Commits follow Conventional Commits with a scope naming the subsystem: `fix(hyprland):`, `feat(omarchy):`, `chore(flake):`, `docs(adr):`. Run `nix fmt` before committing.

Architecture decisions get an ADR in `docs/adr/` (see `template.md`).

## Docs

- README's auto-generated mermaid section — start here to understand the wiring
- `INSTALL.md` — sakura-specific install guide (LUKS + BTRFS + flakes)
- `INSTALL-UME.md` — ume migration runbook and destructive-work decision gates
- `OMARCHY_DISCREPANCY_REPORT.md` — historical port-time audit (2026-09-01) that fed ADR-0007; still a useful v4 architecture reference, no longer status
- `docs/omarchy/quattro-port-inventory.md` — historical port-time inventory (same caveat)
- `docs/omarchy-parity-backlog.md` — follow-ups, re-scoped post-migration (see its addendum)
- `docs/adr/` — architecture decision records (0013 = Den adoption, 0014 = trust boundaries, 0015 = OpenCode supply chain, 0016 = OpenCode V2 migration, 0017 = multi-host modeling)
- `docs/omarchy/` — research briefs on upstream Omarchy
- `thoughts/` — in-progress plans and drafts (not authoritative)

`AGENTS.md` is a symlink to this file — edit `CLAUDE.md` only.
