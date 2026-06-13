# ADR-0003: Fix Plymouth Theme Asset Paths and Add Background Image

## Status

Accepted

## Context

The custom kebun Plymouth theme showed a blank/black screen during boot. The LUKS password prompt was functional (keystrokes were captured) but entirely invisible — no logo, no progress bar, no background colour.

Root cause: the theme descriptor (`kebun.plymouth`) used relative-style paths for `ImageDir` and `ScriptFile`:

```
ImageDir=/share/plymouth/themes/kebun
ScriptFile=/share/plymouth/themes/kebun/kebun.script
```

These paths don't exist as absolute filesystem paths anywhere on the system. Plymouth's `Image()` function resolves filenames relative to `ImageDir`, so when `ImageDir` resolves to a nonexistent directory, every `Image("logo.png")` call fails silently. The script aborts before even setting the background colour, resulting in a completely blank screen.

The NixOS Plymouth module (`nixos/modules/system/boot/plymouth.nix`) rewrites `/nix/store/.../share/plymouth/themes` paths in `.plymouth` files for the initrd, but only matches the Nix store prefix pattern. The broken `/share/plymouth/themes/kebun` path was never rewritten, leaving it invalid both in the initrd and in the running system.

Additionally, the progress bar was positioned at `Window.GetHeight() / 2 + 80`, which overlaps with the password dialog area when LUKS prompts for a passphrase.

## Decision

1. **Fix asset paths**: Change `ImageDir` and `ScriptFile` in `kebun.plymouth` to use `$out`-based absolute Nix store paths (`$themeDir` variable in the derivation), so the NixOS Plymouth module can correctly rewrite them for the initrd.

2. **Add a background image**: Generate a 1920×1080 PNG with a solid cyan fill and a subtle darker vignette, loaded as a background sprite at Z-order 0 behind all other elements.

3. **Move progress bar to bottom**: Reposition the progress bar from screen-centre offset to `Window.GetHeight() - height - 40`, keeping it clear of the centred password dialog.

4. **Add explicit Z-ordering**: Assign `SetZ()` values to all sprites (background=0, UI=10–12) to prevent layering ambiguity.

### Files changed

- `packages/plymouth-theme-kebun/default.nix` — rewrote `.plymouth` descriptor to use `$themeDir` absolute paths; added `background.png` generation; repositioned progress bar to bottom in script; added Z-order and background sprite.

## Consequences

### Positive

- **Plymouth now renders correctly**: Logo, background, progress bar, and password dialog all display during boot
- **Password prompt is visible**: LUKS passphrase entry shows the lock icon, entry field, and bullet dots
- **Progress bar out of the way**: Moved to bottom of screen so it doesn't overlap the password dialog
- **Initrd paths are correct**: `$out`-based paths get rewritten by the NixOS module for the initrd environment

### Negative

- **Background image adds ~19 KiB** to the initrd theme directory (negligible)
- **Background is a static PNG**: On very small or very large screens the 1920×1080 image will be top-left anchored rather than scaled to fit. Plymouth's `Sprite` API does not stretch images — this is acceptable for a boot splash shown briefly

### Neutral

- **Cyan background colour still set** via `Window.SetBackgroundTopColor/BottomColor` as before — the background image layer sits on top of this
- **Font remains `Cantarell 11`**: Not present in the initrd font set (DejaVuSans is the default). Font only affects `label-pango`/`label-freetype` plugin text rendering, which the kebun script never uses — no functional impact

## References

- [NixOS Plymouth module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/plymouth.nix) — initrd theme path rewriting logic (lines 253–274)
- [Plymouth script API](https://www.freedesktop.org/wiki/Software/Plymouth/ScriptAPI/) — `Image()`, `Sprite()`, `SetZ()`, `SetOpacity()`
- ADR-0001 (original system architecture)

## Notes

- Date proposed: 2026-06-13
- Date accepted: 2026-06-13
- Proposed by: ivokun (blank screen observed on boot)
- Accepted by: ivokun