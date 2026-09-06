# ADR-0009: Patch the Vendored Omarchy Environment for NixOS at Build Time

## Status

Accepted

## Context

The first real deploy to sakura (2026-09-04) failed in a way that all prior
eval-only verification could not catch: the QuickShell never started. The top
bar was missing, and Super+Space / Super+K did nothing.

Root cause: the vendored Omarchy v4.0.2 tree keeps its upstream Arch shebangs.
Of the 431 scripts in the environment's `bin/`, 438 shebangs across the tree
read `#!/bin/bash` and 5 read `#!/usr/bin/python3`. NixOS has no `/bin`, so
the kernel returns ENOENT on exec. The failure is **silent** — no coredump,
no log line; `omarchy-launch-shell` died instantly at boot, and QProcess in
the shell reported "binary could not be found" for scripts that were present.

Two aggravating factors:

1. `wrapProgram` made it worse, not better: it relocates the original file
   verbatim to `.name-wrapped` (keeping the dead `#!/bin/bash`) and generates
   a correct outer wrapper that execs it. Every wrapped entry script was
   therefore still broken.
2. The Stage 2 comment that verbatim upstream scripts were "inert on NixOS"
   was stale after the Stage 4 stack swap: the shell's QML spawns upstream
   verbs by name for widget data and IPC (`omarchy-reminder`,
   `omarchy-monitor-state`, `omarchy-capture-*`, `AppLibrary` → `gtk-launch`,
   the menu's floating-terminal helper → `xdg-terminal-exec`, …). They are
   live runtime dependencies.

A second class of breakage surfaced once the shell ran: upstream menu items
whose actions assume Arch machinery — pacman/AUR installs, runtime theme and
channel switching, config "refresh" scripts that would clobber HM-managed
files, the factory reset, limine direct boot, NetworkManager DNS (kebun is
iwd per ADR-0002), and mise dev-envs. Some of these are merely broken; one
(factory reset) is dangerous, and one class (refresh-*) is destructive to
state HM owns.

## Decision

Treat the vendored tree as **verbatim upstream content, patched at build
time** — never fork the files in the repo.

### 1. Tree-wide shebang rewrite before wrapping (`packages/omarchy/default.nix`)

Rewrite shebangs across the whole tree (bin/, shell/ plugins, default/
helpers) **before** `wrapProgram`, because wrapProgram relocates originals
verbatim into `.name-wrapped` — a broken shebang there survives the wrap.

- `#!/bin/bash` → `${pkgs.bash}/bin/bash`
- `#!/usr/bin/python3` → `${pkgs.python3.withPackages (p: [ p.pygobject3 ])}/bin/python3`
  (PyGObject is required by `omarchy-file-select`'s D-Bus portal client;
  the other four python scripts are stdlib-only)

Embedded heredoc shebangs inside Arch-only dev tooling
(`omarchy-mise-install`, `omarchy-upgrade-to-quattro`, …) are deliberately
left untouched: rewriting strings inside scripts risks corrupting them, and
those tools have no NixOS meaning.

### 2. Runtime dependencies for the verbs the shell actually spawns

`runtimeDeps` gains: `xdg-terminal-exec` (backs ~40 floating-terminal menu
actions), `zbar` (QR capture), `localsend` (share), `gpu-screen-recorder`
(screen recording). grim/slurp/hyprpicker/tesseract/ffmpeg were already
installed and only needed PATH visibility.

`gtk-launch` ships inside gtk3's `bin/` but NixOS never exposes it; the
shell's `AppLibrary.qml` launches desktop entries via `uwsm app -- gtk-launch …`,
which resolves through the **user-manager** PATH — so `pkgs.gtk3` goes into
`home.packages` (landing on `/etc/profiles/per-user` PATH), not into the
wrapped scripts' PATH.

### 3. xdg-terminal-exec default terminal

`xdg.terminal-exec.enable` with `Alacritty.desktop` as default (matching
`TERMINAL` in `envs.lua`) so the Default Terminal Execution Specification
resolver finds a real terminal at the greeter and in menu actions.

### 4. Hide Arch-only menu items via the sanctioned override point

The shell merges `~/.config/omarchy/extensions/omarchy-menu.jsonc`
field-by-field by id over its vendored default menu (MenuModel.js). Kebun
stages an HM-managed override that sets `when: "false"` on 24 ids —
inheriting upstream icon/label, trivially reversible per item:

- Theme machinery (`style.theme/background/unlock/font`) — the palette is
  single-sourced at build time instead (ADR-0007 Stage 5, extended to the
  greeter in ADR-0011)
- Pacman/AUR packaging (`install.package/aur/tui`, `remove.package/tui/theme`, …)
- Upstream update machinery (`update.omarchy`, channel switching, config
  refresh scripts, extra themes)
- Arch-only setup (`setup.reset` — factory reset, `setup.direct-boot` —
  limine, `setup.security` — Arch flows, `setup.network.dns` — NM)
- mise dev-env trees (no mise on kebun; NixOS handles toolchains)
- `learn.herdr-keybindings` (no herdr)

## Consequences

### Positive

- The silent-ENOENT failure class is eliminated for the whole vendored tree,
  not just the entry points
- The menu is fully launchable: every visible item either works or was
  deliberately hidden; nothing dangerous (factory reset) remains reachable
- Versions move with the pinned env — a flake bump re-audits in one place
- Hidden items return by deleting one line each if kebun ports equivalents

### Negative

- Upstream drift: an env bump can add scripts with Arch shebangs again — the
  rewrite is tree-wide, so it self-heals, but new **interpreter** kinds
  (perl, ruby, …) would need a rule added
- The menu override must be revisited when upstream changes menu ids
- `omarchy-pkg-present`-gated items silently vanish on NixOS (pacman is
  absent), which is desired but implicit

### Neutral

- The stage-2 "inert scripts" comment is rewritten; the wrapping mechanism
  itself is unchanged

## References

- Upstream install/login flow: omacom/omarchy `install/login/*.sh`
- ADR-0002 (iwd), ADR-0007 (Quattro migration stages)
- `packages/omarchy/default.nix`, `home/features/omarchy-shell.nix`

## Notes

- Date proposed: 2026-09-06
- Date accepted: 2026-09-06
- Proposed by: ivokun + agent session (first-deploy debugging)
- Accepted by: ivokun
