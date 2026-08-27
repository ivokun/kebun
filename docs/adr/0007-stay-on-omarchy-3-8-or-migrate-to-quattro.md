# ADR-0007: Stay on Omarchy 3.8.x or Migrate to Quattro (v4)

## Status

**Proposed** — needs a decision. Recorded now because the situation changed
underneath the repo and continuing by default is itself a choice.

## Context

Kebun is a port of Omarchy's desktop to NixOS idioms, and has tracked the
v3.8.x stable line since inception. That line has stopped moving.

Verified on 2026-08-27 against a fresh fetch of `basecamp/omarchy`:

- **v4.0.0 was released on 2026-08-14**; **v4.0.1** followed on 2026-08-25.
  The previous parity report still described v4 as an in-development alpha.
- **`quattro` is now the upstream default branch.** `git ls-remote --symref
  origin HEAD` returns `refs/heads/quattro`. An older local clone's cached
  `origin/HEAD` still says `master` and is misleading.
- **Commit cadence since the v4.0.0 tag: `master` 1, `quattro` 110.** The
  single commit on `master` is the 3.8.5 release bump itself.
- 3.8.5 ships a migration (`1786465483.sh`) that fires a critical desktop
  notification inviting users to upgrade, wired via a new `mako` rule to
  `omarchy-upgrade-to-quattro` — a 2447-line migration tool shipped inside
  the 3.8.5 release.

So the branch kebun mirrors is in backport-only maintenance, and upstream is
actively steering users off it.

**What v4 actually changed.** `git diff --stat v3.8.4..v4.0.0` is 1876 files,
+104k/−14k lines. This is not a release, it is a rewrite:

- **waybar and walker are gone.** `git ls-tree -r v4.0.0 | grep -iE
  'waybar|walker'` returns nothing. Bar, launcher, notifications, OSD, and
  lock screen are now one QuickShell (Qt Quick/QML) application under
  `shell/`, absorbing what kebun currently spreads across `waybar.nix`, the
  walker/elephant wiring in `desktop.nix`, and the mako/swayosd/hyprlock
  sections of `hyprland.nix`.
- **Hyprland is configured in Lua**, using Hyprland's native Lua API plus an
  Omarchy `o.bind(keys, description, dispatcher)` wrapper. Every file under
  `config/hypr/` and `default/hypr/` is `.lua`. The `bindd`-with-description
  convention that `menu-keybindings` depends on (and that CLAUDE.md documents
  as mandatory) is replaced by binding metadata carried in the Lua source.
- Omarchy itself now ships as **pacman packages from a dedicated repo**
  across four channels, and blocks direct `pacman -Syu` in favour of
  `omarchy update`. This packaging model has no meaning for kebun.

The porting cost is therefore concentrated in exactly the two largest and
most-edited modules in the repo: `home/features/hyprland.nix` (~700 lines) and
`home/features/waybar.nix`, plus the walker/elephant configuration.

Two mitigating facts: `quickshell` is packaged in nixpkgs (with a Home Manager
`programs.quickshell` module), and Home Manager supports Hyprland Lua config.
Neither reduces the amount of *config* that has to be re-derived; they only
mean the dependencies exist.

## Decision

**Deferred.** The realistic options are:

1. **Stay on 3.8.x, explicitly.** Accept that upstream is frozen and treat
   kebun as owning its own desktop from here. Cheap now; the reference
   implementation stops receiving fixes and the gap widens permanently.
2. **Migrate to Quattro.** Rewrite the shell stack around QuickShell and the
   Hyprland Lua config. Expensive, and pulls in a QML application that must be
   maintained as config rather than as a package.
3. **Hybrid: keep the v3.8-shaped stack, cherry-pick from v4.** Continue with
   waybar/walker/mako/swayosd, but track quattro for individual behaviours
   worth having. Lowest risk, but v4's changes are mostly *architectural*, so
   there is less to cherry-pick than the commit count suggests.

Whichever is chosen, it should be recorded here rather than arrived at by
inaction, because option 1 is what happens if nothing is decided.

## Consequences

### Positive

- Naming the choice makes the maintenance burden visible instead of letting it
  accumulate as unexplained drift in the parity report.
- If option 1 is taken, the parity report can stop being scored against a
  moving target and become a record of deliberate divergence.

### Negative

- Option 1 means no upstream fixes. The 3.8.x-era bugs already fixed in
  quattro (FIDO2 predictable tmp path, USB-device-name Lua injection, DNS
  helper PATH pinning, git transport-helper URL guards) will need porting by
  hand or accepting.
- Option 2 invalidates a large share of `hyprland.nix` and all of
  `waybar.nix`, and the CLAUDE.md `bindd` convention along with them.

### Neutral

- The defects fixed in the 2026-08-27 batch (unwired services, USB-C power
  profile, DND toggle) are independent of this decision and needed either way.

## References

- `OMARCHY_DISCREPANCY_REPORT.md` — full 3.8.5 parity audit, 2026-08-27
- `docs/omarchy/omarchy_porting.md` §4.3 — theme-porting strategies
- Upstream: `basecamp/omarchy`, tags `v4.0.0` (2026-08-14), `v4.0.1` (2026-08-25)

## Notes

- Date proposed: 2026-08-27
- Date accepted: —
- Proposed by: Salahuddin Muhammad Iqbal (with Claude Code)
- Accepted by: —
