# Kebun Review Fixes — Implementation Plan

## TL;DR

Fix 9 Critical, 10 High, and key Medium issues from the review of the Omarchy feature port. Changes span 5 files across 3 execution waves.

## Context

- **Original Request**: Review recent changes (5 commits porting Omarchy desktop features to NixOS)
- **Review Findings**: 9 Critical, 10 High, 8+ Medium issues
- **User Decisions**:
  - `move-waybar` -> **Remove entirely**
  - `gnome-control-center` -> **Remove**
  - `ffmpeg` -> **Switch to `ffmpeg-headless`**
  - `iwd` -> **Remove `wireless.iwd.enable`**

## Work Objectives

All keybindings, menus, TUI launchers, and utility scripts work correctly on a NixOS rebuild, with proper UWSM integration, no command injection, no config conflicts, and no missing packages.

---

## Execution Strategy

### Wave 1: Critical Fixes (independent, can all run in parallel)

| Task | File(s) | SubAgent | Reason |
|------|---------|-----------|--------|
| 1.1 Fix iwd config conflict | `networking.nix` | @bug-hunter | Simple one-line fix |
| 1.2 Fix lid switch bug | `hyprland.nix` | @bug-hunter | Need to differentiate on/off |
| 1.3 Fix toggle-mirror-display | `scripts/default.nix` | @bug-hunter | Add toggle-off detection |
| 1.4 Fix launch-or-focus security+robustness | `scripts/default.nix` | @bug-hunter | Remove eval, add set -euo pipefail, fix regex |
| 1.5 Add uwsm app -- to all TUI launchers | `scripts/default.nix` | @bug-hunter | UWSM compliance |
| 1.6 Add walker overlay to flake.nix | `flake.nix` | @backend-architect | Ensure pkgs.walker == inputs.walker |
| 1.7 Remove move-waybar script + keybinding | `scripts/default.nix`, `hyprland.nix`, `common.nix` | @refactor-specialist | Declarative model |
| 1.8 Remove gnome-control-center + ffmpeg->headless | `common.nix` | @refactor-specialist | Package cleanup |

### Wave 2: High Priority Fixes (after Wave 1 completes)

| Task | File(s) | SubAgent | Reason |
|------|---------|-----------|--------|
| 2.1 Fix toggle-laptop-display safety | `scripts/default.nix` | @bug-hunter | Exit on no display, safe .disabled default |
| 2.2 Add timeouts to show-weather | `scripts/default.nix` | @bug-hunter | Offline handling |
| 2.3 Filter media files in transcode | `scripts/default.nix` | @bug-hunter | Only show media files in picker |
| 2.4 Qualify all unquoted binary paths | `scripts/default.nix` | @refactor-specialist | Nix store path consistency |
| 2.5 Fix menu-omarchy unqualified commands | `scripts/default.nix` | @refactor-specialist | Use full Nix paths |
| 2.6 Fix menu-keybindings modmask | `scripts/default.nix` | @bug-hunter | Proper bitmask decoding |
| 2.7 Fix launch-tui/launch-floating-terminal setsid+uwsm | `scripts/default.nix` | @bug-hunter | Proper process management |
| 2.8 Add missing scripts to common.nix | `common.nix` | @bug-hunter | Ensure all referenced scripts are in PATH |

### Wave 3: Medium Priority + Polish (after Wave 2)

| Task | File(s) | SubAgent | Reason |
|------|---------|-----------|--------|
| 3.1 Fix cycle-monitor-scaling float comparison | `scripts/default.nix` | @bug-hunter | Normalize floats |
| 3.2 Fix file-manager-cwd fallback chain | `scripts/default.nix` | @bug-hunter | Remove .title fallback |
| 3.3 Fix close-all-windows race condition | `scripts/default.nix` | @bug-hunter | Collect then close |
| 3.4 Fix screenrecord-menu output spec | `scripts/default.nix` | @bug-hunter | Add -g flag |
| 3.5 Fix reminder-set empty input | `scripts/default.nix` | @bug-hunter | Use /dev/null |
| 3.6 Fix dictation scripts to use Nix paths | `scripts/default.nix` | @refactor-specialist | Path consistency |
| 3.7 Remove menu-theme placeholder | `scripts/default.nix` | @refactor-specialist | Remove non-functional option or implement |

---

## Detailed TODOs

### Task 1.1: Fix iwd networking conflict
- **What to do**: Remove `networking.wireless.iwd.enable = true;` line from `hosts/common/networking.nix`. Keep `networking.networkmanager.wifi.backend = "iwd";` which is sufficient.
- **Must NOT do**: Do not remove the `wifi.backend` line -- that's the correct way to use iwd with NetworkManager.
- **SubAgent**: @bug-hunter
- **Acceptance Criteria**: `networking.nix` has no `wireless.iwd.enable` line; `wifi.backend = "iwd"` remains; file compiles with `nix flake check`.

### Task 1.2: Fix lid switch bindings
- **What to do**: Change `toggle-laptop-display` to accept an argument (`on`/`off`). Update the `bindl` section:
  ```nix
  bindl = [
    ", switch:on:Lid Switch, exec, toggle-laptop-display off"
    ", switch:off:Lid Switch, exec, toggle-laptop-display on"
  ];
  ```
  Update the `toggle-laptop-display` script to handle args:
  - `toggle-laptop-display off` -> disable internal display
  - `toggle-laptop-display on` -> enable internal display
  - `toggle-laptop-display` (no arg) -> toggle current state (backward compat)
- **Must NOT do**: Do not change the script to only support args -- keep toggle mode as default for backward compatibility.
- **SubAgent**: @bug-hunter
- **References**: `home/features/hyprland.nix` lines 514-517, `packages/scripts/default.nix` lines 590-604
- **Acceptance Criteria**: Lid close disables internal display; lid open re-enables it.

### Task 1.3: Fix toggle-mirror-display (add toggle-off)
- **What to do**: Check `.mirrorOf` field from `hyprctl monitors -j` on the secondary monitor. If it has a value, the display is currently mirrored -> un-mirror it. If empty, mirror it.
  ```bash
  CURRENT_MIRROR=$(hyprctl monitors -j | jq -r --arg sec "$SECONDARY" '.[] | select(.name == $sec) | .mirrorOf // empty')
  if [ -n "$CURRENT_MIRROR" ]; then
    hyprctl keyword monitor "$SECONDARY,preferred,auto,1"  # un-mirror
  else
    hyprctl keyword monitor "$SECONDARY,preferred,auto,1,mirror,$PRIMARY"
  fi
  ```
- **Must NOT do**: Do not use state files -- rely on hyprctl runtime state.
- **SubAgent**: @bug-hunter
- **Acceptance Criteria**: Running the script toggles between mirrored and independent. Running twice returns to original state.

### Task 1.4: Fix launch-or-focus (security + robustness)
- **What to do**: 
  1. Add `set -euo pipefail` at the top
  2. Remove `eval exec setsid $LAUNCH_COMMAND` -- replace with direct execution:
     ```bash
     if [ -n "$WINDOW_ADDRESS" ]; then
       ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow "address:$WINDOW_ADDRESS"
     else
       shift  # remove WINDOW_PATTERN arg
       exec uwsm app -- "$@"
     fi
     ```
  3. Change the calling convention: `launch-or-focus <pattern> <command> [args...]` where command is always a separate argument.
  4. Fix regex: use `contains()` or escape dots in pattern:
     ```bash
     .[] | select((.class | ascii_downcase | contains($p | ascii_downcase))
       or (.title | ascii_downcase | contains($p | ascii_downcase))) | .address
     ```
  5. Use `${pkgs.util-linux}/bin/setsid` if keeping setsid (see task 2.7).
- **Must NOT do**: Do not keep `eval` with any form of quoting fix -- eliminate `eval` entirely.
- **SubAgent**: @bug-hunter
- **References**: `packages/scripts/default.nix` lines 308-323
- **Acceptance Criteria**: `launch-or-focus "org.kebun.wiremix" uwsm app -- alacritty --class org.kebun.wiremix -e wiremix` works correctly. No `eval` in script.

### Task 1.5: Add `uwsm app --` wrapper to all TUI launchers
- **What to do**: Update each launcher script to use `uwsm app --` in the launch command:
  - `launch-audio`: Change second arg of `launch-or-focus` to include `uwsm app --`
  - `launch-wifi`: Same
  - `launch-bluetooth`: Same
  - `launch-activity`: Same
  - `launch-tui`: Already has `uwsm app --`, keep it
  - `launch-floating-terminal`: Already has `uwsm app --`, keep it
  
  Since task 1.4 changes `launch-or-focus` calling convention, each caller must pass the command as separate args:
  ```bash
  exec launch-or-focus "org.kebun.wiremix" "uwsm" "app" "--" "${pkgs.alacritty}/bin/alacritty" "--class" "org.kebun.wiremix" "-e" "wiremix"
  ```
  OR simplify by having the specific launchers bypass `launch-or-focus` and implement the focus-or-launch directly with `uwsm app --`.
- **Must NOT do**: Do not remove focus-or-launch pattern -- it's useful for preventing duplicate windows.
- **SubAgent**: @bug-hunter
- **Acceptance Criteria**: All TUI apps launch via `uwsm app --` and show up in `systemd --user` scope list.

### Task 1.6: Add walker overlay to flake.nix
- **What to do**: Add walker to the existing `nixpkgs.overlays` block in `flake.nix`:
  ```nix
  nixpkgs.overlays = [
    (final: prev: {
      walker = inputs.walker.packages.${prev.system}.walker;
      deno = prev.deno.overrideAttrs (old: {
        checkFlags = (old.checkFlags or []) ++ [
          "--skip" "uv_compat::tests::tty_reset_mode_restores_termios"
        ];
      });
    })
  ];
  ```
  This ensures `${pkgs.walker}` in scripts resolves to the flake input version, not nixpkgs.
- **Must NOT do**: Do not remove the existing deno overlay.
- **SubAgent**: @backend-architect
- **Acceptance Criteria**: `nix flake check` passes. `pkgs.walker` resolves to the same version as `inputs.walker`.

### Task 1.7: Remove move-waybar script + keybindings + package reference
- **What to do**: 
  1. Remove the `move-waybar` script from `packages/scripts/default.nix` (lines ~533-558)
  2. Remove the four `move-waybar` keybindings from `home/features/hyprland.nix` (lines ~445-448):
     ```
     "SUPER SHIFT CTRL, LEFT, Move Waybar left, exec, move-waybar left"
     "SUPER SHIFT CTRL, RIGHT, Move Waybar right, exec, move-waybar right"
     "SUPER SHIFT CTRL, UP, Move Waybar up, exec, move-waybar up"
     "SUPER SHIFT CTRL, DOWN, Move Waybar down, exec, move-waybar down"
     ```
  3. Remove `move-waybar` from the scripts list in `home/common.nix`
- **Must NOT do**: Do not leave dead references to `move-waybar`.
- **SubAgent**: @refactor-specialist
- **Acceptance Criteria**: No references to `move-waybar` anywhere. `nix flake check` passes.

### Task 1.8: Remove gnome-control-center + switch ffmpeg to headless
- **What to do**:
  1. Remove `gnome-control-center` from `home/common.nix` packages
  2. Remove `gnome-control-center` package reference from `menu-hardware` and `menu-omarchy` scripts (the "Settings" option)
  3. Change `ffmpeg` to `ffmpeg-headless` in `home/common.nix` packages
  4. Change `${pkgs.ffmpeg}` to `${pkgs.ffmpeg-headless}` in the `transcode` script
  5. For the `menu-omarchy` "Settings" option, remove it or replace with system settings alternatives that exist (nm-connection-editor, blueman-manager, pavucontrol -- which all have dedicated launchers already)
- **Must NOT do**: Do not leave menu options pointing to removed commands.
- **SubAgent**: @refactor-specialist
- **Acceptance Criteria**: `gnome-control-center` not in package list. `ffmpeg-headless` used everywhere. Menu options don't reference removed commands.

---

### Task 2.1: Fix toggle-laptop-display safety
- **What to do**:
  1. Remove hardcoded `eDP-1` fallback; exit with error notification if no internal display found
  2. Use `// false` default for `.disabled` field
  3. Support `on`/`off` args from task 1.2
  ```bash
  if [ -z "$INTERNAL" ]; then
    notify-send "Display" "No internal display found"
    exit 1
  fi
  ```
- **Acceptance Criteria**: Script exits gracefully on headless machines.

### Task 2.2: Add timeouts to show-weather
- **What to do**: Add `--max-time 5` and `--connect-timeout 5` to both curl calls. Add error handling for failed calls.
- **Acceptance Criteria**: Script completes in <=6 seconds when offline.

### Task 2.3: Filter media files in transcode
- **What to do**: Add `-iname` filters for common media extensions:
  ```bash
  find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n'
  ```
- **Acceptance Criteria**: Walker only shows media files, not text/docs.

### Task 2.4: Qualify all unquoted binary paths
- **What to do**: Replace all bare command names with `${pkgs...}/bin/...`:
  | Command | Replacement | Script |
  |---------|------------|--------|
  | `google-chrome` | `${pkgs.google-chrome}/bin/google-chrome` | menu-omarchy |
  | `nvim` | `${pkgs.neovim}/bin/nvim` | menu-omarchy |
  | `nautilus` | `${pkgs.nautilus}/bin/nautilus` | menu-omarchy, file-manager-cwd |
  | `gnome-control-center` | REMOVED (task 1.8) | menu-omarchy, menu-hardware |
  | `swaybg` | `${pkgs.swaybg}/bin/swaybg` | menu-background |
  | `swayosd-client` | `${pkgs.swayosd}/bin/swayosd-client` | menu-hardware |
  | `hyprmagnifier` | `${pkgs.hyprmagnifier}/bin/hyprmagnifier` | cursor-zoom |
  | `hyprwhspr-rs` | `${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs` | dictation-* |
  | `setsid` | `${pkgs.util-linux}/bin/setsid` | launch-or-focus, launch-tui, launch-floating-terminal |
  | `localsend` | `${pkgs.localsend}/bin/localsend` | localsend-share |
- **Note**: The scripts module `default.nix` only receives `pkgs` -- verify all referenced packages are available. `swayosd` is in `hosts/common/desktop.nix` system packages, not necessarily in `pkgs` scope of the scripts module -- check if it needs to be added.
- **Must NOT do**: Do not add packages that don't exist in the scripts module's `pkgs` scope -- verify each one.
- **Acceptance Criteria**: All binaries in scripts use Nix store paths. No bare command names.

### Task 2.5: Fix menu-omarchy unqualified commands
- **What to do**: Same as 2.4 but specifically for menu-omarchy. Also remove "Settings" option (gnome-control-center removed). Replace `$TERMINAL` with `${pkgs.alacritty}/bin/alacritty` or reference the `$TERMINAL` env var with a fallback:
  ```bash
  "Terminal") uwsm app -- ${pkgs.alacritty}/bin/alacritty ;;
  ```
- **Acceptance Criteria**: All commands in menu-omarchy use full Nix paths.

### Task 2.6: Fix menu-keybindings modmask
- **What to do**: Replace the hardcoded bitmask lookup table with proper jq bitmask decoding:
  ```jq
  def decode_modmask:
    [. as $mod |
      (if ($mod / 64 | floor) % 2 >= 1 then "SUPER" else empty end),
      (if ($mod % 2) >= 1 then "SHIFT" else empty end),
      (if ($mod / 4 | floor) % 2 >= 1 then "CTRL" else empty end),
      (if ($mod / 8 | floor) % 2 >= 1 then "ALT" else empty end)
    ] | if length > 0 then join(" + ") + " + " else "" end;
  ```
  Only decode SHIFT/CTRL/ALT/SUPER (bits 0, 2, 3, 6) -- ignore CAPS/MOD5 as irrelevant for keybind display.
- **Acceptance Criteria**: All modifier combinations display correctly, no `MOD:N` entries.

### Task 2.7: Fix setsid + uwsm interaction
- **What to do**: 
  - In `launch-tui`: Replace `setsid uwsm app -- alacritty` with just `exec uwsm app -- alacritty` (uwsm already handles process grouping)
  - In `launch-or-focus`: Remove `setsid` entirely, use `exec uwsm app --` directly
  - In `launch-floating-terminal`: Same
  - In `cursor-zoom`: Replace `hyprmagnifier &` with `uwsm app -- hyprmagnifier` (the `&` background is also incorrect with uwsm)
- **Must NOT do**: Do not remove `uwsm app --` -- it's required for systemd integration.
- **Acceptance Criteria**: All launched processes appear under `systemd --user` scope.

### Task 2.8: Verify all referenced scripts are in common.nix
- **What to do**: Cross-reference all script names in `common.nix`'s `with scripts; [...]` list against:
  1. Scripts defined in `packages/scripts/default.nix`
  2. Scripts referenced in `hyprland.nix` keybindings
  3. Scripts referenced in `waybar.nix` on-click handlers
  4. Scripts referenced by other scripts (e.g., `menu-capture` calls `screenshot`, `screenshot-clipboard`, `color-picker`, `screenrecord`)
  
  The review already verified these are all present. But verify that `screenshot`, `screenshot-clipboard`, `color-picker`, `screenrecord`, `toggle-nightlight`, `toggle-gaps`, `toggle-layout`, `toggle-waybar`, `battery-remaining-time`, `check-updates` are all in the `with scripts; [...]` block. (From the review, they ARE in the pre-existing list -- this is just a verification step.)
- **Acceptance Criteria**: `grep -r` for all script names in keybindings/menus finds matching entries in common.nix.

---

### Task 3.1: Fix cycle-monitor-scaling float comparison
- **What to do**: Normalize `CURRENT` to 2 decimal places with `printf "%.2f"` before comparing.
- **Acceptance Criteria**: `1` and `1.00` and `1.0` all normalize to `1.00`.

### Task 3.2: Fix file-manager-cwd fallback chain
- **What to do**: Remove `.title` from the jq chain:
  ```bash
  CWD=$(hyprctl activewindow -j | jq -r '.workingDirectory // empty')
  [ -z "$CWD" ] && CWD="$HOME"
  [ ! -d "$CWD" ] && CWD="$HOME"
  ```
- **Acceptance Criteria**: Never attempts to `cd` into a window title string.

### Task 3.3: Fix close-all-windows race condition
- **What to do**: Collect all addresses first, then close:
  ```bash
  mapfile -t ADDRESSES < <(hyprctl clients -j | jq -r '.[].address')
  for addr in "${ADDRESSES[@]}"; do
    hyprctl dispatch closewindow "address:$addr" || true
  done
  ```
- **Acceptance Criteria**: No address-shift race conditions.

### Task 3.4: Fix screenrecord-menu output spec
- **What to do**: Add output geometry for full-screen recording:
  ```bash
  OUTPUT_GEOM=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width)x\(.height)\(.x),\(.y)"')
  wl-screenrec -g "$OUTPUT_GEOM" -f "$OUTPUT"
  ```
  OR just use `-g` without args for full screen. Verify `wl-screenrec` syntax.
- **Acceptance Criteria**: Full-screen recording captures the correct monitor.

### Task 3.5: Fix reminder-set empty input
- **What to do**: Replace `echo "" | walker --dmenu` with `walker --dmenu </dev/null`.
- **Acceptance Criteria**: Walker opens cleanly without empty stdin issues.

### Task 3.6: Fix dictation scripts to use Nix paths
- **What to do**: Replace `command -v hyprwhspr-rs` + bare `hyprwhspr-rs` with `${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs`. Since the package IS in `home.packages`, it will be in PATH, but using the Nix path is consistent:
  ```bash
  if [ -x ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs ]; then
    ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs record toggle
  ```
- **Acceptance Criteria**: Dictation works even if PATH is unusual.

### Task 3.7: Remove non-functional menu-theme option
- **What to do**: Either:
  - (a) Remove "Rose Pine Moon (dark)" from menu-theme since it can't actually switch themes
  - (b) Remove the entire `menu-theme` script and its keybinding since theme switching requires a rebuild
  - (c) Replace with a notification saying "Theme switching requires rebuild -- edit `home/features/theme-rose-pine.nix`"
  
  Recommended: option (b) -- remove `menu-theme` script and the `SUPER SHIFT CTRL, SPACE` keybinding, since the whole menu is non-functional for themes.
- **Acceptance Criteria**: No dead/placeholder menu options.

---

## Dependency Matrix

| Task | Depends On | Blocks |
|------|------------|--------|
| 1.1 | -- | -- |
| 1.2 | -- | 2.1 |
| 1.3 | -- | -- |
| 1.4 | -- | 1.5 |
| 1.5 | 1.4 | 2.7 |
| 1.6 | -- | -- |
| 1.7 | -- | -- |
| 1.8 | -- | 2.4, 2.5 |
| 2.1 | 1.2 | -- |
| 2.2 | -- | -- |
| 2.3 | -- | -- |
| 2.4 | 1.8 | -- |
| 2.5 | 1.8 | -- |
| 2.6 | -- | -- |
| 2.7 | 1.5 | -- |
| 2.8 | -- | -- |
| 3.1-3.7 | -- | -- |

## Verification Strategy

After all changes are applied:

1. **`nix flake check`** -- Must pass with zero errors
2. **`nix fmt`** -- Must produce no changes (alejandra formatter)
3. **Grep for dead references**: `grep -r 'move-waybar\|gnome-control-center' home/ packages/ hosts/` should return nothing
4. **Grep for `eval` in scripts**: `grep 'eval' packages/scripts/default.nix` should only return unrelated uses (none expected)
5. **Grep for bare `setsid`**: `grep -n 'setsid' packages/scripts/default.nix` -- should use `${pkgs.util-linux}/bin/setsid` or be removed
6. **Verify all scripts in PATH**: Build the system and test that each keybinding fires without "command not found"
7. **Test lid switch**: Close/open lid and verify internal display toggles correctly
8. **Test mirror toggle**: Run toggle-mirror-display twice -- should mirror then un-mirror
9. **Test TUI launchers**: Click waybar icons for audio/wifi/bluetooth and verify they use uwsm scope
10. **Test offline weather**: Run `show-weather` with network disconnected -- should complete within 6 seconds

## Success Criteria

- [ ] All Critical fixes (C1-C9) implemented and verified
- [ ] All High fixes (H1-H10) implemented and verified
- [ ] Key Medium fixes (M1-M7) implemented
- [ ] `nix flake check` passes
- [ ] `nix fmt` produces no changes
- [ ] No bare command references remain in scripts
- [ ] No `eval` with user input remains
- [ ] All `uwsm app --` wrappers present
- [ ] Walker overlay in place
- [ ] iwd config conflict resolved

---

Plan complete. Switch to a build subagent (like `@bug-hunter` or `@refactor-specialist`) to begin execution, starting with Wave 1 tasks.
