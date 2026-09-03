# ADR-0007: Stay on Omarchy 3.8.x or Migrate to Quattro (v4)

## Status

**Accepted (2026-09-01) — Migrate to Quattro, staged.**

## Context

Kebun is an Omarchy-derived NixOS desktop for `sakura` (ThinkPad X13 Gen 1, AMD
Renoir) and tracked the v3.8.x stable line since inception. That line is dead.

Verified on 2026-09-01 against upstream (releases API) and a live v4 install:

- **v4.0.0** (2026-08-14), **v4.0.1** (2026-08-25), **v4.0.2** (2026-08-31). The two
  patch releases are security-driven, from a newly formed upstream security team; signed
  packages are now required; omarchy.org/security exists.
- **`master` (3.8.x) has received zero commits since the v3.8.5 tag on 2026-08-14.**
  Not backport-only — frozen, including for security fixes.
- Upstream moved `basecamp/omarchy` → **`omacom/omarchy`** (org rename; old URLs
  redirect).
- The **reference install lives on IVOKUN-HTPC** (hostname `ivokun-htpc`, a B550M
  desktop running Arch + Omarchy 4.0.2, upgraded to quattro the same day). It is a
  **separate machine** — kebun is edited and built there but deploys only to `sakura`.

What v4 is, verified live (full inventory in `OMARCHY_DISCREPANCY_REPORT.md` §2 and
`docs/omarchy/quattro-port-inventory.md`):

- One **QuickShell** (Qt6/QML) process hosts bar, launcher/menus, notifications, OSD,
  lock screen, idle, nightlight, polkit agent, clipboard — as plugins. Shipped plugins
  live under `$OMARCHY_PATH/shell/`; user state in `~/.config/omarchy/shell.json`
  (runtime-mutated, no deep-merge — user file replaces defaults); third-party plugins
  git-clone into `~/.config/omarchy/plugins/` with inotify hot-reload. Everything is
  driven from scripts through one IPC wrapper: `omarchy-shell <target> <method> [args]`
  = `qs ipc -n -p "$OMARCHY_PATH/shell" call -- …`. The supervisor is
  `omarchy-launch-shell` (restart budget, compositor-liveness check).
- **Hyprland is configured in Lua.** `hl.*` is Hyprland 0.56's native Lua API; omarchy
  layers `o.bind(keys, description, dispatcher, opts)` on top in `default/hypr/helpers.lua`.
  The defaults tree (`~20` files) is self-contained and vendored wholesale; the user
  layer is a 5-line `hyprland.lua` requiring defaults then user modules. Requires
  **Hyprland 0.56+**; kebun's compositor lock was frozen at 0.54.0 (April) while
  scripts' `pkgs.hyprland` hyprctl was 0.56.0 — the skew is Stage 1's target.
- **Theming** is omarchy's own `omarchy-theme-set` engine: a `colors.toml` palette
  renders 17 `default/themed/*.tpl` targets, atomically swaps
  `~/.local/state/omarchy/current/theme/`, and pushes the live palette into the running
  shell (`applyTheme` IPC). **Aether is a separate, optional GUI engine** (Go/Wails,
  webkit2gtk) that targets the *v3* app set — it is not v4's theme path and not in
  nixpkgs.
- NetworkManager replaces iwd in v4 (kebun deliberately uses iwd, ADR-0002). Foot is
  v4's default terminal. Omarchy ships as signed pacman packages across four channels
  — no NixOS meaning.
- Availability: nixpkgs carries `quickshell` 0.3.0 (the Arch reference ships 0.3.1
  **stable** from its own repo — no git pin; the earlier "quickshell-git pin" claim was
  wrong), plus `gpu-screen-recorder`, `herdr`, `voxtype`. `aether` and `tensaku` are
  not packaged (irrelevant for Stage 5, which ports omarchy's engine).

### Premise correction (2026-09-01, same day as the draft)

The draft's central obstacle — a shared `$HOME` between an "Arch tenant" and kebun,
with three escalating failure modes and a `.bak` graveyard — was **a wrong premise**.
The Arch/Omarchy install is a different machine. The `~/.config/hypr` forensics
describe the HTPC's own omarchy state and its v3→v4 migration residue, not an
HM-vs-omarchy conflict. "Logically blocked while the Arch tenant lives" is void, the
ownership treaty and tripwire are unnecessary, and migration is unblocked. Downstream
items invalidated: backlog §0.8 (tripwire) and §2.5 (shared-$HOME leftovers) are N/A;
backlog §3.1's "live monitor layout" was the HTPC's monitors, not sakura's — verify on
sakura before touching `home/sakura.nix`.

### Cost framing

The porting cost is concentrated in `home/features/hyprland.nix` (820 lines → Lua
port), `home/features/waybar.nix` (309 lines → deleted), the walker/elephant wiring in
`hosts/common/desktop.nix` (→ deleted), and the ~20 scripts driving v3 components
(port surface inventoried in `docs/omarchy/quattro-port-inventory.md` §4). The
`bindd` list maps 1:1 onto `o.bind` lines, so bindings port mechanically; the shell,
theme, and script layers are the real work. v4's runtime-mutated state model
(`shell.json`, plugins/, toggles/) means the NixOS port manages shipped **defaults**
only and lets user state win — mirroring v4's own layering.

## Decision

**Migrate kebun to the Quattro architecture (option 2)** — accepted by the user on
2026-09-01, explicitly overriding the draft's hybrid recommendation (which rested on
the dissolved shared-$HOME obstacle). Staged:

- **Stage 1 — Compositor** (independent of the shell swap): pin the `hyprland` flake
  input to `v0.56.2`; point every script's `hyprctl` at the compositor package
  (kills the 0.54 compositor / 0.56 client skew); land the opacity retune and a
  fail-soft `menu-keybindings`. Runtime gates at the first sakura rebuild:
  re-validate the ADR-0004 lock guard and the ADR-0006 suspend path on this Renoir
  hardware (cannot be verified from the HTPC).
- **Stage 2 — Ship the v4 shell**: `quickshell` from nixpkgs; vendor the shell plugin
  tree and the thin `bin/` IPC wrappers (`omarchy-shell`, `omarchy-menu`, `omarchy-osd`,
  `omarchy-notification-send`, `omarchy-system-lock`, `omarchy-toggle-*`) as Nix
  derivations; satisfy the `OMARCHY_PATH` contract by pointing it at the vendored
  store path (name kept for upstream file compatibility); supervisor as a uwsm-wrapped
  `exec-once` per kebun's UWSM mandate (v4 itself uses a raw exec — deliberate
  divergence). Runtime deps to declare: `inotifywait`, `jq`.
- **Stage 3 — Hyprland config → Lua**: vendor `default/hypr/` wholesale; port the
  `bindd` list 1:1 onto `o.bind` (descriptions preserved, so `hyprctl -j binds` and
  `menu-keybindings` keep working); kebun defaults (monitors, autostart, input,
  window rules) as kebun modules required after the omarchy defaults; honor the
  `_G.omarchy_default_bindings = false` kill-switch model where useful.
- **Stage 4 — Stack swap**: quickshell takes over bar/launcher/menus/notifications/
  OSD/lock/idle/nightlight. Remove the waybar/walker/elephant/mako/swayosd/hyprlock/
  hypridle/hyprsunset modules and services; port scripts per the inventory: menus →
  `omarchy-shell` IPC verbs, `notify-send` → `omarchy-notification-send`, retire
  `toggle-waybar`/`restart-waybar`/`restart-walker`/`check-waybar-updates`. Carry the
  hard-won invariants (zero-output repair from `hyprlock-guard`, `wake-display`,
  ADR-0004/0006 behavior) into the lock/idle wrappers.
- **Stage 5 — Theme engine**: port the `omarchy-theme-set-templates` model — one
  `colors.toml` + per-app templates rendered at build time (Nix replaces the runtime
  templater where convenient), replacing the per-file hardcoded hexes (backlog §4.2).
  Rose Pine Dawn becomes a `colors.toml`. Aether stays out.
- **Stage 6 — Cleanup**: retire transition pieces; rewrite CLAUDE.md (`bindd` →
  `o.bind` conventions; walker/elephant/waybar guidance removed); update the report
  and backlog to post-migration state; record divergences.

Deliberate divergences retained through migration: **iwd** (ADR-0002 — the NM
migration is out of scope), the **Rose Pine Dawn** palette, **ghostty/kitty**
terminals (foot is v4's default; revisit separately), kebun's **own script set**
(adopt v4 integration points, not all 428 upstream commands), and the **UWSM mandate**
for launched apps.

## Consequences

### Positive

- Escapes the frozen 3.8.x integration; upstream is the target again and the parity
  report becomes a porting map instead of a scoreboard against a dead branch.
- Modern, maintained shell stack; the v4.0.1/v4.0.2 security work and future waves
  arrive with the architecture instead of needing hand-porting.
- No ownership treaty needed — reference and target are separate machines.

### Negative

- Invalidates most of `hyprland.nix`, all of `waybar.nix`, the walker/elephant stack,
  the CLAUDE.md `bindd` convention, and ~20 scripts driving v3 components.
- Pins kebun to quickshell 0.3.x behavior (nixpkgs 0.3.0 vs the reference's 0.3.1 —
  verify plugin compatibility at Stage 2; bump via nixpkgs or a quickshell flake if
  needed).
- HM must manage only shell *defaults*; `shell.json`, `plugins/`, and `toggles/` are
  user/runtime state and must stay out of home-manager's symlinked paths.

### Neutral

- The 2026-08-27 defect fixes and backlog §0 items 1/4 (browser-flags path, X webapp
  match) are stack-independent. v3-component items (waybar idle indicator, mako/swayosd
  callers) are superseded when Stage 4 lands — fix only what is still needed then.
- The skew fix and opacity retune from Stage 1 carry into the Lua port unchanged.

## References

- `docs/omarchy/quattro-port-inventory.md` — live port inventory (IPC surface, Lua
  layer, theme engine, script port surface), 2026-09-01
- `OMARCHY_DISCREPANCY_REPORT.md` — v4.0.2 audit, 2026-09-01 (esp. §2 inventory, §3
  security)
- `docs/omarchy-parity-backlog.md` — re-scoped as the migration checklist
- `docs/adr/0002` (iwd), `0004` (lock guard), `0006` (suspend) — retained constraints
- Upstream: `omacom/omarchy` tags `v4.0.0`–`v4.0.2`; reference install on IVOKUN-HTPC

## Notes

- Date proposed: 2026-08-27
- Updated with v4.0.2 evidence + recommendation: 2026-09-01
- Premise corrected (reference machine is a separate Arch box, not a tenant):
  2026-09-01
- **Date accepted: 2026-09-01 — option 2 (Migrate), overriding the hybrid
  recommendation**
- Proposed by: Salahuddin Muhammad Iqbal (with Claude Code)
- Accepted by: Salahuddin Muhammad Iqbal

### Outcome (2026-09-03)

All six stages shipped: `f55ead0` (ADR accepted), `183fe3a` (port inventory),
`0d37faa` (Stage 1 — compositor pin + hyprctl routing), `f071a0d` (Stage 2 — vendored
shell environment), `9eeebc5` (Stage 3 — Hyprland Lua port), `15e1f64` (Stage 4 —
stack swap), `2953acc` (Stage 5 — palette single-sourcing + build-time theme render),
plus the Stage 6 cleanup/docs commit.

Deviations discovered during implementation, all recorded in the tree:

- **Idle-suspend listener dropped.** v3's hypridle 900s suspend listener was not
  carried; idle is the shell plugin now (screensaver 150s / lock 300s from shell.json).
- **makoctl restore bind → history.** The v4 shell IPC has no "restore last
  notification" verb; the SUPER+SHIFT+ALT+comma bind surfaces history instead
  (`hyprland.nix`, bindings.lua).
- **DND carve-out behavior change** — the mako notify-send carve-out is gone with mako;
  silencing state moved to the shell (`~/.local/state/omarchy/notifications.json`).
- **`wake-display` is consumerless** pending ADR-0006 revalidation at deploy — its v3
  consumers were retired with the stack swap.
- **Menu sinks are `omarchy-menu-select`/`-input`** (the shell menu's dmenu mode);
  upstream's JSONC route tree is used for the shell's own system menus only.
- **Theme staged at build time**, byte-identical to the reference machine's staged
  shell.toml (vendored renderer in `packages/omarchy/theme.nix`, palette in
  `lib/palette.nix`).

Deploy caveat: verification so far is eval-only from the HTPC — the Stage 3+4 runtime
gates (shell renders, PAM unlock, idle timings, ADR-0004/0006 revalidation) are still
pending on sakura. Also note upstream's `version` file is stale: it reads
`4.0.0.alpha` even at tag `v4.0.2` (verified on the reference machine), so don't use
it to verify a bumped vendored tree — check the upstream git tag instead.
