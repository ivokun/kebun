# ADR-0011: Port the Upstream Omarchy SDDM Greeter and Re-Skin It With the Kebun Palette

## Status

Accepted

## Context

Removing autologin (ADR-0010) made the SDDM greeter visible for the first
time, and it became the machine's only password prompt — so it had to look
right. Two problems:

1. **Wrong compositor.** The NixOS SDDM module's Wayland support offers only
   kwin or weston; it ran the greeter under **Weston kiosk**. Upstream runs
   its greeter under **Hyprland** with a dedicated minimal config
   (`default/sddm/hyprland.lua`) — the omarchy theme is designed against
   that, and under Weston it rendered badly.
2. **Wrong palette.** The upstream theme is Tokyo Night dark (`#1a1b26`
   background; `#C0CAF5` icons/bullets/entry frame; `#F7768E` failed states;
   the green `#A8CD76` omarchy logo PNG). Kebun is Rose Pine Dawn light with
   a single-sourced palette (`lib/palette.nix`), and the user wants an
   IVOKUN wordmark instead of the omarchy logo.

Additionally, the greeter session does not inherit the desktop's input
configuration: its keyboard layout defaults to `us`, and the mismatch
produced failed logins at the greeter for symbol-heavy passwords.

## Decision

Stage the greeter from the pinned vendored env and re-skin it at build time.

### 1. Theme package (`hosts/common/desktop.nix`, `sddmThemeOmarchy`)

Copy `default/sddm/omarchy` from the pinned env into
`share/sddm/themes/omarchy` and add it to `environment.systemPackages` —
SDDM discovers themes in XDG data dirs (NixOS 26.11 has no
`sddm.themes` option). Sourcing from the env keeps the theme version-locked
to the shell (same store path the shell already imports; nothing rebuilds
twice). The old `where-is-my-sddm-theme` package is dropped.

### 2. Hyprland as the greeter compositor

`services.displayManager.sddm.settings.Wayland.CompositorCommand` is
overridden directly (the module's `wayland.compositor` enum only offers
kwin/weston; user settings win over module defaults):

```
<pinned hyprland>/bin/start-hyprland -- --config /etc/sddm-greeter/hyprland.lua
```

Absolute paths keep the sddm service free of PATH assumptions. The greeter
config is the vendored upstream `default/sddm/hyprland.lua` (standalone —
`hl.*` is Hyprland's native Lua API) with **kebun's input delta appended**:

```lua
hl.config({ input = { kb_layout = "jp" } })
```

staged via `environment.etc."sddm-greeter/hyprland.lua"`.

### 3. Build-time re-skin, palette single-sourced

All colors interpolate from `lib/palette.nix` — the same file the shell
theme renders from — so greeter and desktop can never drift:

- `Main.qml`: `#1a1b26` → `palette.background` (`#faf4ed`, light mode)
- Asset recolor **channel-wise** (`-channel RGB -opaque`, alpha preserved):
  `#C0CAF5` → `palette.foreground` for bullet/lock/entry,
  `#F7768E` → `palette.red` (Dawn love) for the failed states — the
  soft-shadow overlay in entry.png is kept (reads as a subtle shadow on
  light)
- `logo.png` regenerated as an **IVOKUN wordmark**: ImageMagick `label:`
  in JetBrainsMono Nerd Font (the theme's font family), filled with
  `palette.accent`, trimmed + bordered to approximate the upstream logo's
  inset. The logo color is a one-word swap if a different palette slot is
  wanted (iris/pine/rose/love).

JetBrainsMono Nerd Font is added to **system** fonts — the greeter user
(`sddm`) only sees `fonts.packages`, not HM user fonts.

### 4. Build-mechanics constraints (learned here, reusable)

- **No shell heredocs inside Nix strings**: alejandra re-indents string
  contents and mangles heredoc terminators, silently changing the builder
  script. The input delta is a separate `pkgs.writeText` derivation
  concatenated in the builder.
- **Store sources are mode 444**: `cp` preserves that, so a follow-up
  `>>`-append fails with "Permission denied". Build the output with a fresh
  redirect (`{ cat a; cat b; } > $out/hyprland.lua`) instead of cp+append.
- The daemon pre-creates `$out` as a directory: `mkdir -p $out` and write
  files inside it; never assume `$out` is absent.

## Consequences

### Positive

- The greeter looks native: upstream layout, kebun palette, IVOKUN identity,
  correct keyboard layout — one coherent login experience
- Palette changes propagate to the greeter on the next rebuild; greeter and
  desktop cannot drift apart
- The theme follows flake input bumps automatically (sourced from the env)
- Greeter kb_layout fixes the failed-login class for symbol-heavy passwords

### Negative

- The compositor override relies on `settings` beating the module's
  generated defaults; a future NixOS sddm module change could need rework
- Upstream theme/QML drift requires re-diffing the re-skin substitutions on
  env bumps (the sed targets are specific hexes)
- The wordmark is generated text, not a designed logo — fine for now;
  replacing it with custom artwork is a drop-in PNG swap

### Neutral

- `where_is_my_sddm_theme` remains installable from nixpkgs if ever needed
  as a fallback; it is no longer referenced by the config

## References

- Upstream: omacom/omarchy `install/login/sddm.sh`, `default/sddm/`
  (theme + greeter Hyprland config)
- ADR-0010 (greeter as the single prompt), ADR-0007 (pinned env model)
- `hosts/common/desktop.nix` (sddmThemeOmarchy, sddmGreeterDelta,
  sddmGreeterHyprland, CompositorCommand override), `lib/palette.nix`

## Notes

- Date proposed: 2026-09-06
- Date accepted: 2026-09-06
- Proposed by: ivokun + agent session
- Accepted by: ivokun
