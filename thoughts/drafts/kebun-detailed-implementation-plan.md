# Kebun Implementation Plan — Detailed & Corrected

> **Based on**: `kebun-implementation-plan.md`  
> **Current state**: ~85% functional, ~80% visual parity  
> **Target**: ~90% overall parity  
> **Constraint**: No Omarchy branding. Single theme (Rose Pine Dawn). NixOS-native approach.

---

## Critical Discrepancies with Original Plan

The original implementation plan has several assumptions that conflict with the current codebase. This plan corrects them:

| # | Original Plan Says | Actual State | Resolution |
|---|-------------------|-------------|------------|
| 1 | Create `home/features/starship.nix` (new file) | Starship already configured in `home/features/shell.nix` | **Extract** starship config from `shell.nix` into a new `starship.nix`, update with Rose Pine Dawn palette, then import in `shell.nix` |
| 2 | Add Rose Pine Dawn theme to tmux via `extraConfig` | Tmux already uses `rose-pine` tmux plugin with `@rose_pine_variant 'dawn'` in `editors.nix` | **Keep plugin** — it handles all theme colors. No manual overrides needed. Add only functional settings (not colors). |
| 3 | ~~Create `home/features/git.nix` (new)~~ | Git config is inside `home/features/editors.nix` alongside neovim/lazygit/tmux | **SKIP** — keep git+lazygit in `editors.nix`. No extraction. Low-value separation. |
| 4 | Create `home/features/fastfetch.nix` (new) | Fastfetch already exists as a **154-line themed config** | **Modify** existing file — replace generic color names (green/blue/cyan/magenta) with Rose Pine Dawn hex colors |
| 5 | Add battery module to waybar | Battery module **already exists** in `waybar.nix` with full config | **Skip** — already done |
| 6 | Create `hosts/common/power.nix` for power-profiles-daemon | `services.power-profiles-daemon.enable = true` already in `hosts/sakura/default.nix` | **Skip** system module. Only need toggle script + waybar custom module. |
| 7 | Keybinding `Super+G` for toggle-gaps | `Super+G` already bound to `togglegroup` | Use **`Super+Alt+G`** for toggle-gaps |
| 8 | `home/features/tmux.nix` | Doesn't exist — tmux is in `editors.nix` | Keep in `editors.nix`. The rose-pine plugin already handles theming. |

---

## Phase 1: Visual Polish (High Impact, Low Effort)

### 1.1 Extract & Theme Starship Prompt

**Status**: Starship exists in `shell.nix` with minimal cyan/red config  
**Action**: Extract to dedicated module + apply Rose Pine Dawn palette  
**Files affected**:
- `home/features/shell.nix` — remove starship `settings` block (keep `enable = true` and integrations)
- `home/features/starship.nix` — **NEW** file with Rose Pine Dawn palette
- `flake.nix` — add `./home/features/starship.nix` to `mkHomeManagerModules` imports

**Current state** (`shell.nix`):
```nix
programs.starship = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;
  settings = {
    add_newline = true;
    command_timeout = 200;
    format = "$directory$git_branch\n$character";
    character = { error_symbol = "[❯](bold red)"; success_symbol = "[❯](bold cyan)"; };
    directory = { truncation_length = 2; truncation_symbol = "…/"; repo_root_style = "bold cyan"; repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) "; format = "[$path](bold cyan) "; };
    git_branch = { format = "([$branch](bold cyan)) "; };
  };
};
```

**New `home/features/starship.nix`** (full):
```nix
{ config, pkgs, ... }: {
  programs.starship = {
    enable = true;
    enableTransience = true;  # honor zsh transient prompt
    
    settings = {
      palette = "rose_pine_dawn";
      
      palettes.rose_pine_dawn = {
        overlay = "#f2e9e1";
        love    = "#b4637a";
        gold    = "#ea9d34";
        rose    = "#d7827e";
        pine    = "#286983";
        foam    = "#56949f";
        iris    = "#907aa9";
        text    = "#575279";
        muted   = "#797593";
      };
      
      add_newline = true;
      command_timeout = 200;
      
      format = "$directory$git_branch$git_status\n$character";
      
      character = {
        success_symbol = "[❯](bold foam)";
        error_symbol   = "[❯](bold love)";
      };
      
      directory = {
        truncation_length  = 2;
        truncation_symbol  = "…/";
        style               = "bold pine";
        repo_root_style     = "bold foam";
        repo_root_format    = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
        format              = "[$path]($style) ";
        read_only           = " ro";
        read_only_style     = "love";
      };
      
      git_branch = {
        style  = "bold iris";
        format = "[$symbol$branch]($style) ";
        symbol = " ";
      };
      
      git_status = {
        style = "bold rose";
        conflicted  = "≠${count} ";
        ahead       = "⇡${count} ";
        behind      = "⇣${count} ";
        diverged    = "⇕⇡${ahead_count}⇣${behind_count} ";
        untracked   = "?${count} ";
        stashed     = "⚑${count} ";
        modified    = "!${count} ";
        staged      = "+${count} ";
        renamed     = "»${count} ";
        deleted     = "✘${count} ";
      };
    };
  };
}
```

**Changes to `shell.nix`**:
```nix
# REPLACE the entire programs.starship block with:
programs.starship = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;
  # Theme configuration is in home/features/starship.nix
  # (imported via flake.nix)
};
```

**Changes to `flake.nix`** — add to mkHomeManagerModules imports:
```nix
./home/features/starship.nix
```

⚠️ **Note on `enableTransience`**: This enables zsh transient prompts (previous commands collapse to a shorter format). If you prefer the full prompt on every line, remove this line. The `starship.nix` module also sets starship integrations, but `shell.nix` still sets `enableZshIntegration`/`enableFishIntegration` to ensure both shells get the prompt.

---

### 1.2 Lazygit Theme (Extend Existing Config)

**Status**: `programs.lazygit.enable = true;` in `editors.nix` with no theme  
**Action**: Add Rose Pine Dawn color settings to existing lazygit config  
**Files affected**: `home/features/editors.nix`

**Add to** `programs.lazygit` block in `editors.nix`:
```nix
programs.lazygit = {
  enable = true;
  settings = {
    gui.theme = {
      activeBorderColor         = [ "#56949f" "bold" ];
      inactiveBorderColor       = [ "#797593" ];
      optionsTextColor           = [ "#907aa9" ];
      selectedLineBgColor        = [ "#f2e9e1" ];
      selectedRangeBgColor       = [ "#f2e9e1" ];
      cherryPickedCommitBgColor  = [ "#56949f" ];
      cherryPickedCommitFgColor  = [ "#faf4ed" ];
      unstagedChangesColor       = [ "#b4637a" ];
      defaultFgColor             = [ "#575279" ];
      searchingActiveBorderColor = [ "#ea9d34" ];
    };
  };
};
```

---

### 1.3 Tmux — KEEP Plugin, No Manual Colors Needed

**Status**: Tmux already uses `rose-pine` tmux plugin with variant `dawn`  
**Action**: No theming changes needed — the plugin handles all colors  
**Rationale**: The original plan suggested adding Rose Pine Dawn colors via `extraConfig`, but this would **conflict** with the `rose-pine` tmux plugin already configured in `editors.nix`. The plugin is the correct NixOS-native approach and already produces the right theme.

---

### 1.4 Update Fastfetch Colors (Modify Existing)

**Status**: `fastfetch.nix` exists (154 lines) with generic color names (`green`, `blue`, `cyan`, `magenta`)  
**Action**: Replace generic color names with Rose Pine Dawn hex colors  
**Files affected**: `home/features/fastfetch.nix`

**Current color keys** (`green`, `blue`, `magenta`) should map to:
- `green` → Rose Pine Dawn `foam` (#56949f) for system info
- `blue` → Rose Pine Dawn `pine` (#286983) for hardware info
- `cyan` → Rose Pine Dawn `foam` (#56949f) for title
- `magenta` → Rose Pine Dawn `iris` (#907aa9) for keys

**Replace the `display.color` and per-module `keyColor` sections**:
```nix
display = {
  color = {
    keys = "#907aa9";      # iris
    title = "#56949f";     # foam
  };
  separator = "  ";
};
```

And each module's `keyColor`:
- System Information section: `keyColor = "#56949f";` (foam) — was `green`
- Hardware Information section: `keyColor = "#286983";` (pine) — was `blue`
- Title: colors → user `#56949f` (foam), host `#907aa9` (iris) — was cyan/blue

---

## Phase 2: Utility Scripts (Medium Effort, High Functional Value)

### 2.1 Battery Monitoring Scripts

**Status**: No battery scripts exist. `acpi` package already in `desktop.nix`. Waybar battery module already exists.  
**Action**: Add 5 battery scripts to `packages/scripts/default.nix`  
**Files affected**:
- `packages/scripts/default.nix` — add scripts
- `home/common.nix` — add scripts to package list
- `home/features/hyprland.nix` — add keybinding

**Scripts to add**:

#### `battery-status` — Show charging state
```nix
battery-status = pkgs.writeShellScriptBin "battery-status" ''
  STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
  echo "$STATUS"
'';
```

#### `battery-capacity` — Show percentage
```nix
battery-capacity = pkgs.writeShellScriptBin "battery-capacity" ''
  ${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100"
'';
```

#### `battery-remaining` — Percentage with icon
```nix
battery-remaining = pkgs.writeShellScriptBin "battery-remaining" ''
  CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
  STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
  if [ "$STATUS" = "Charging" ]; then
    ICON="󰂄"
  elif [ "$CAP" -ge 80 ]; then
    ICON="󰁹"
  elif [ "$CAP" -ge 60 ]; then
    ICON="󰂁"
  elif [ "$CAP" -ge 40 ]; then
    ICON="󰁾"
  elif [ "$CAP" -ge 20 ]; then
    ICON="󰁽"
  else
    ICON="󰂃"
  fi
  echo "$ICON $CAP%"
'';
```

#### `battery-remaining-time` — Time estimate
```nix
battery-remaining-time = pkgs.writeShellScriptBin "battery-remaining-time" ''
  NOW=/sys/class/power_supply/BAT0/energy_now
  PWR=/sys/class/power_supply/BAT0/power_now
  if [ -f "$NOW" ] && [ -f "$PWR" ]; then
    N=$(${pkgs.coreutils}/bin/cat "$NOW")
    P=$(${pkgs.coreutils}/bin/cat "$PWR")
    if [ "$P" -gt 0 ] 2>/dev/null; then
      MINUTES=$(echo "scale=0; ($N * 60) / $P" | ${pkgs.bc}/bin/bc)
      HOURS=$(echo "scale=1; $MINUTES / 60" | ${pkgs.bc}/bin/bc)
      echo "$HOURS hours"
    else
      echo "Charging"
    fi
  else
    echo "N/A"
  fi
'';
```

#### `battery-monitor` — Background low-battery warning
```nix
battery-monitor = pkgs.writeShellScriptBin "battery-monitor" ''
  while true; do
    CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
    STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Discharging" ] && [ "$CAP" -le 15 ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Battery Low" "Battery at $CAP% — connect charger!"
    elif [ "$STATUS" = "Discharging" ] && [ "$CAP" -le 25 ]; then
      ${pkgs.libnotify}/bin/notify-send -u normal "Battery" "Battery at $CAP%"
    fi
    ${pkgs.coreutils}/bin/sleep 120
  done
'';
```

**Add packages to `home/common.nix`**:
```nix
# Add to home.packages list alongside existing scripts:
battery-status
battery-capacity
battery-remaining
battery-remaining-time
battery-monitor
```

**Also add `bc` to `home/common.nix` packages** (needed by `battery-remaining-time`):
```nix
bc
```

**Keybinding in `hyprland.nix`** (add to `bindd` list):
```nix
"SUPER SHIFT, B, Show battery status, exec, ${pkgs.libnotify}/bin/notify-send \"Battery\" \"$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 'N/A')% ($(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Unknown'))\""
```

---

### 2.2 Keyboard Backlight Toggle — SKIPPED

**Decision**: The ThinkPad X13 Gen 1 does not have a keyboard backlight. This script is skipped entirely.

---

### 2.3 Mic Mute Toggle Script

**Status**: `XF86AudioMicMute` already mapped to `swayosd-client --input-volume mute-toggle` in hyprland keybindings  
**Action**: Add script as alternative (can be bound to different key or used in waybar module)  
**Files affected**: `packages/scripts/default.nix`, `home/common.nix`

```nix
mic-mute = pkgs.writeShellScriptBin "mic-mute" ''
  ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle
  MUTE=$(${pkgs.pulseaudio}/bin/pactl get-source-mute @DEFAULT_SOURCE@ | ${pkgs.gnugrep}/bin/grep -oP '(?<=Mute: )\w+')
  if [ "$MUTE" = "yes" ]; then
    ${pkgs.libnotify}/bin/notify-send "Microphone" "Muted" --icon=audio-input-microphone-muted
  else
    ${pkgs.libnotify}/bin/notify-send "Microphone" "Unmuted" --icon=audio-input-microphone
  fi
'';
```

> **Note**: The original plan uses a complex `pactl list sources | grep | awk` pipeline to check mute state. A simpler approach is `pactl get-source-mute @DEFAULT_SOURCE@` which directly returns `Mute: yes/no`. The script above uses this simpler method.

---

### 2.4 Window Gap Toggle

**Status**: Super+G already bound to `togglegroup`  
**Action**: Use `Super+Alt+G` instead  
**Files affected**: `packages/scripts/default.nix`, `home/common.nix`, `home/features/hyprland.nix`

```nix
toggle-gaps = pkgs.writeShellScriptBin "toggle-gaps" ''
  STATE_FILE="$XDG_RUNTIME_DIR/hypr-gaps-state"
  if [ -f "$STATE_FILE" ]; then
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 5
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 10
    rm -f "$STATE_FILE"
    ${pkgs.libnotify}/bin/notify-send "Gaps" "Normal spacing"
  else
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 0
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 0
    touch "$STATE_FILE"
    ${pkgs.libnotify}/bin/notify-send "Gaps" "No gaps"
  fi
'';
```

**Keybinding** (add to `bindd` list):
```nix
"SUPER ALT, G, Toggle window gaps, exec, toggle-gaps"
```

---

### 2.5 Layout Toggle (Dwindle ↔ Master)

**Action**: Add toggle script + keybinding  
**Files affected**: `packages/scripts/default.nix`, `home/common.nix`, `home/features/hyprland.nix`

```nix
toggle-layout = pkgs.writeShellScriptBin "toggle-layout" ''
  CURRENT=$(${pkgs.hyprland}/bin/hyprctl getoption general:layout | ${pkgs.gawk}/bin/awk 'NR==1 {print $2}')
  if [ "$CURRENT" = "dwindle" ]; then
    ${pkgs.hyprland}/bin/hyprctl keyword general:layout master
    ${pkgs.libnotify}/bin/notify-send "Layout" "Master layout"
  else
    ${pkgs.hyprland}/bin/hyprctl keyword general:layout dwindle
    ${pkgs.libnotify}/bin/notify-send "Layout" "Dwindle layout"
  fi
'';
```

**Keybinding**:
```nix
"SUPER CTRL, M, Toggle layout dwindle/master, exec, toggle-layout"
```

> ⚠️ **Conflict check**: `SUPER CTRL, L` is currently mapped to "Lock system" (`hyprlock`). Need to pick a different binding. Options:
> - `SUPER CTRL, SLASH` — layout toggle
> - `SUPER CTRL, M` — master/dwindle (M for master)
> 
> **Recommended**: `SUPER CTRL, M`

---

### 2.6 Power Profile Toggle Script

**Status**: `services.power-profiles-daemon.enable = true` already in `hosts/sakura/default.nix`  
**Action**: Add toggle script only (no new system module needed)  
**Files affected**: `packages/scripts/default.nix`, `home/common.nix`

```nix
toggle-power-profile = pkgs.writeShellScriptBin "toggle-power-profile" ''
  CURRENT=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)
  if [ "$CURRENT" = "power-saver" ]; then
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced
    ${pkgs.libnotify}/bin/notify-send "Power Profile" "Balanced"
  elif [ "$CURRENT" = "balanced" ]; then
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
    ${pkgs.libnotify}/bin/notify-send "Power Profile" "Performance"
  else
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
    ${pkgs.libnotify}/bin/notify-send "Power Profile" "Power Saver"
  fi
'';
```

⚠️ **Note**: `power-profiles-daemon` package must be in systemPackages for the CLI tool. Check if it's already pulled in by the service. If not, add to `hosts/sakura/default.nix` or `hosts/common/desktop.nix`:
```nix
environment.systemPackages = [ pkgs.power-profiles-daemon ];
```

---

### 2.7 Screenshot OCR

**Action**: Add script + package  
**Files affected**: `packages/scripts/default.nix`, `home/common.nix`, `home/features/hyprland.nix`

```nix
screenshot-ocr = pkgs.writeShellScriptBin "screenshot-ocr" ''
  ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" /tmp/ocr-tmp.png
  ${pkgs.tesseract}/bin/tesseract /tmp/ocr-tmp.png stdout | ${pkgs.wl-clipboard}/bin/wl-copy
  ${pkgs.libnotify}/bin/notify-send "OCR" "Text copied to clipboard"
  rm -f /tmp/ocr-tmp.png
'';
```

**Add `tesseract` to `home/common.nix` packages** (for OCR engine).

**Keybinding**:
```nix
"SUPER CTRL, PRINT, Screenshot OCR, exec, screenshot-ocr"
```

---

## Phase 3: Application Configurations

### 3.1 Helix Editor

**Status**: Not currently installed or configured  
**Action**: Create new feature module  
**Package**: `helix` 25.07.1 available in nixpkgs  
**Files affected**:
- `home/features/helix.nix` — **NEW**
- `flake.nix` — add `./home/features/helix.nix` to imports
- `home/common.nix` — no need to add package (helix module enables it)

**New `home/features/helix.nix`**:
```nix
{ config, pkgs, ... }: {
  programs.helix = {
    enable = true;
    defaultEditor = false; # Neovim remains default editor
    
    settings = {
      theme = "rose_pine_dawn";
      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        auto-save = true;
        indent-guides.render = true;
        bufferline = "multiple";
        soft-wrap.enable = true;
        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
      };
      
      keys.normal = {
        space.space = "file_picker";
        space.w = ":w";
        space.q = ":q";
        space.f = "file_picker";
        space.b = "buffer_picker";
        "C-f" = ":fmt";  # format on Ctrl-f
      };
    };
  };
}
```

> **Note**: Helix has `rose_pine_dawn` theme built-in. No external theme package needed.

---

### 3.2 mpv Configuration

**Status**: `mpv` package already in `home/common.nix`  
**Action**: Add `programs.mpv` config to a new feature module  
**Files affected**:
- `home/features/mpv.nix` — **NEW**
- `flake.nix` — add `./home/features/mpv.nix` to imports

**New `home/features/mpv.nix`**:
```nix
{ config, pkgs, ... }: {
  programs.mpv = {
    enable = true;
    
    config = {
      profile = "gpu-hq";
      force-window = "immediate";
      hwdec = "auto-safe";
      keep-open = "yes";
      save-position-on-quit = "yes";
      force-seekable = "yes";
      osc = "no";
      border = "no";
      background-color = "#faf4ed";
      screenshot-template = "%F_%P";
      screenshot-directory = "~~desktop/";
    };
    
    scripts = with pkgs.mpvScripts; [
      uosc        # Modern customizable UI
      thumbfast   # Thumbnail preview on seek bar
    ];
    
    # uosc theme configuration (Rose Pine Dawn inspired)
    scriptOpts = {
      uosc = {
        font = "CaskaydiaMono Nerd Font";
        font_size = 16;
        background = "#faf4ed";
        background_text = "#797593";
        foreground = "#575279";
        foreground_text = "#faf4ed";
        accent = "#56949f";
        curve = 0;
        bar_color = "#56949f";
        timeline_size = 30;
        controls = "play_pause,chapter_prev,chapter_next,volume,loop,audio,sub,video,playlist,fullscreen";
      };
    };
  };
}
```

> ⚠️ **Important**: Since `mpv` is already in `home.packages` in `common.nix`, using `programs.mpv.enable = true` will take over management. Need to **remove `mpv` from `home.packages` in `common.nix`** to avoid conflicts. Home-manager's `programs.mpv` handles package installation.

---

### 3.3 Fastfetch Color Update

**Status**: Already covered in Phase 1.4 above  
**Action**: Modify existing `home/features/fastfetch.nix` to use Rose Pine Dawn hex colors  
**No new file needed** — just replace the color definitions.

---

### 3.4 Chromium Policies — SKIPPED

**Decision**: No Chromium/Chrome browser policies needed. This section is intentionally omitted.

---

## Phase 4: System Integration

### 4.1 File Descriptor Limits

**Status**: Not currently configured  
**Action**: Add to `hosts/common/core.nix`  
**Files affected**: `hosts/common/core.nix`

Add at the end (before the closing `}`):
```nix
# ─── File Descriptor Limits ───
boot.kernel.sysctl = {
  "fs.file-max" = 2097152;
  "fs.inotify.max_user_watches" = 524288;
};

security.pam.loginLimits = [{
  domain = "*";
  type = "soft";
  item = "nofile";
  value = "2097152";
}];
```

---

### 4.2 Snapper Configuration (Btrfs Snapshots)

**Status**: Not configured. System uses BTRFS (confirmed in hardware-configuration.nix).  
**Package**: `snapper` 0.13.0 available in nixpkgs  
**Action**: Create new system module  
**Files affected**:
- `hosts/common/snapper.nix` — **NEW**
- `hosts/sakura/default.nix` — add import for snapper config (host-specific, since subvolume paths differ)

**New `hosts/common/snapper.nix`**:
```nix
{ pkgs, ... }: {
  services.snapper = {
    cleanupInterval = "1d";
    filters = ''
      # Exclude directories that shouldn't be snapshoted
      + /.cache
      + /.local/share/Trash
      + /node_modules
      + /.git
    '';
  };
}
```

**Add to `hosts/sakura/default.nix`** (host-specific config — home snapshots only):
```nix
# ─── Btrfs Snapshots (home only) ───
services.snapper.configs = {
  home = {
    SUBVOLUME = "/home";
    ALLOW_USERS = [ "ivokun" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 10;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_MONTHLY = 12;
  };
};

# Ensure snapshot directory exists
systemd.tmpfiles.rules = [
  "d /home/.snapshots 0755 ivokun users -"
];
```

⚠️ **Pre-requisite**: Btrfs subvolume `@home` must have a `.snapshots` directory. Verify by checking:
```bash
ls -la /home/.snapshots 2>/dev/null || echo "Need to create .snapshots subvolume"
```

> **Note**: Snapper needs the `.snapshots` subvolume to exist under the snapshotted subvolume. The `systemd.tmpfiles.rules` above creates this directory, but for BTRFS it should ideally be a subvolume. This might require manual setup before first rebuild.

---

### 4.3 Hibernation — NOT FEASIBLE (Current Disk Layout)

**Status**: Hibernation is **not feasible** with the current disk layout.  
**Action**: Skip hibernation configuration. No changes needed.

**Investigation findings**:

| Resource | Size | Hibernation-compatible? |
|----------|------|--------------------------|
| RAM | 30 GiB total | Reserve must be ≥ RAM size |
| LUKS swap partition (`nvme0n1p3`) | 8.8 GiB | ❌ **Way too small** (needs ≥ 30 GiB) |
| zram0 (compressed swap) | 15.3 GiB | ❌ **Cannot hibernate to zram** (zram is RAM-backed) |
| `/sys/power/resume` | `0:0` | ⚠️ Not configured (no resume device set) |
| `/sys/power/state` | `freeze mem disk` | Kernel supports hibernate, just swap is too small |

**Why it doesn't work**:
- Hibernate writes RAM contents to a swap device. The LUKS swap partition at 8.8 GiB cannot hold 30 GiB of RAM contents.
- zram swap lives in RAM itself — writing RAM contents to zram would be circular and is not supported by the kernel hibernate mechanism.
- `/sys/power/resume` is `0:0`, meaning no resume partition has been configured.

**What would be needed to enable hibernation** (future reference — requires repartitioning):
- **Option A**: Repartition the LUKS swap device (`nvme0n1p3`) to be at least 32 GiB (≥ RAM + small margin). This requires shrinking another partition and is risky on a BTRFS layout.
- **Option B**: Create a swapfile on the BTRFS filesystem. Supported since kernel 5.0+, but requires:
  - `nodatacow` attribute on the swapfile directory
  - `compress=no` attribute on the swapfile
  - The swapfile must be a NOCOW file on a non-snapshotted subvolume
  - A `resume_offset` kernel parameter (from `btrfs inspect-namespace map-swapfile`)
  - This is the recommended approach for BTRFS systems and avoids repartitioning, but still requires careful setup.
- **Either option** would also need:
  - `boot.resumeDevice` set in NixOS config
  - Kernel parameter `resume=` pointing to the swap device
  - If using a swapfile: additional `resume_offset=` kernel parameter

> ⚠️ **Decision**: Skip hibernation for now. The current suspend-to-RAM (s2idle/deep) works fine. If hibernation is needed in the future, Option B (BTRFS swapfile) is recommended over repartitioning.

---

### 4.4 Power Profiles Daemon

**Status**: Already enabled in `hosts/sakura/default.nix` with `services.power-profiles-daemon.enable = true;`  
**Action**: No system module changes needed. Only the toggle script (Phase 2.6) and waybar module (Phase 5.2) are needed.

---

### 4.5 WireMix (Audio Mixer)

**Status**: Not installed. `wiremix` 0.10.0 available in nixpkgs.  
**Action**: Simple package addition  
**Files affected**: `home/common.nix`

**Add to `home.packages`** in `common.nix`:
```nix
wiremix
```

> WireMix is a TUI audio mixer for PipeWire. Launch with: `uwsm app -- alacritty -e wiremix`. No config file needed.

---

## Phase 5: Waybar Enhancement

### 5.1 Battery Module

**Status**: ✅ **ALREADY DONE** — Battery module is fully configured in `waybar.nix` with:
- `battery` in `modules-right`
- States, format, format-icons, format-charging, tooltip-format
- CSS styling with `.warning` and `.critical` colors

**Action**: Skip — no changes needed.

---

### 5.2 Power Profile Custom Module

**Action**: Add custom module to waybar + entry to modules-right  
**Files affected**: `home/features/waybar.nix`

**Add to `modules-right`** (after `"battery"`):
```nix
"custom/power"
```

**Add module config**:
```nix
"custom/power" = {
  format = "{}";
  exec = "powerprofilesctl get 2>/dev/null || echo ''";
  interval = 5;
  tooltip = true;
  on-click = "toggle-power-profile";
  return-type = "json";
  exec-on-event = true;
};
```

**Add CSS styling** (in the `style` block):
```css
#custom-power {
  min-width: 12px;
  margin: 0 7.5px;
}
```

---

## Bug Fixes (Discovered During Analysis)

### B1. Duplicate Mako Entry in Exec-Once

**Status**: `hyprland.nix` contains `"uwsm app -- mako"` twice in `exec-once` list (lines ~433-434)  
**Action**: Remove the duplicate

**Change in `home/features/hyprland.nix`**:
```nix
exec-once = [
  "uwsm app -- mako"
  # REMOVED: duplicate "uwsm app -- mako"
  "uwsm app -- waybar"
  ...
];
```

---

### B2. Layout Toggle Keybinding Conflict

**Status**: Original plan suggests `SUPER CTRL, L` for layout toggle, but this is already bound to "Lock system" (`hyprlock`)  
**Action**: Use `SUPER CTRL, M` (M for master layout) instead

---

### B3. Gap Toggle Keybinding Conflict

**Status**: Original plan suggests `SUPER, G` for gap toggle, but this is already bound to `togglegroup`  
**Action**: Use `SUPER ALT, G` for gap toggle instead

---

## Complete File Inventory

### New Files (8 files)

| File | Phase | Description | Lines (est.) |
|------|-------|-------------|-------------|
| `home/features/starship.nix` | 1 | Rose Pine Dawn themed prompt | ~55 |
| `home/features/helix.nix` | 3 | Helix editor config | ~35 |
| `home/features/mpv.nix` | 3 | mpv player config | ~35 |
| `hosts/common/snapper.nix` | 4 | Snapper base config | ~15 |

### Modified Files (8 files)

| File | Phase | Changes |
|------|-------|---------|
| `home/features/shell.nix` | 1 | Remove starship settings block (keep enable + integrations) |
| `home/features/editors.nix` | 1 | Add lazygit theme settings |
| `home/features/fastfetch.nix` | 1 | Replace color names with hex colors |
| `home/features/hyprland.nix` | 2 | Add keybindings, fix duplicate mako |
| `home/features/waybar.nix` | 5 | Add power profile module |
| `home/common.nix` | 2,3,4 | Add new scripts + packages (bc, tesseract, wiremix, helix removal of mpv) |
| `packages/scripts/default.nix` | 2 | Add 7 new scripts |
| `hosts/sakura/default.nix` | 4 | Add snapper config |
| `hosts/common/core.nix` | 4 | Add sysctl + PAM limits |
| `flake.nix` | 1,3 | Add starship.nix, helix.nix, mpv.nix to imports |

### Files NOT Created (Original Plan Had These, But They're Not Needed)

| File | Reason |
|------|--------|
| `home/features/git.nix` | Git config stays in `editors.nix` — no extraction needed |
| `home/features/chromium.nix` | No Chromium/Chrome browser policies needed — SKIPPED |
| `home/features/tmux.nix` | Tmux stays in `editors.nix` — rose-pine plugin already handles theme |
| `home/features/fastfetch.nix` (new) | Already exists — just needs color update |
| `home/features/wiremix.nix` | Too simple for a dedicated file — just a package |
| `hosts/common/power.nix` | Already enabled in `hosts/sakura/default.nix` |
| `hosts/common/system.nix` | File doesn't exist; changes go in `hosts/common/core.nix` |

---

## Implementation Order

### Step 1: Visual Polish (Phase 1) — Day 1-2

| Order | Task | File | Est. Time | Risk |
|-------|------|------|-----------|------|
| 1.1 | Create `starship.nix` with Rose Pine Dawn palette | NEW | 15 min | Low |
| 1.2 | Update `shell.nix` — remove starship settings, keep enable+integrations | MODIFY | 5 min | Low |
| 1.3 | Add `starship.nix` to `flake.nix` imports | MODIFY | 2 min | Low |
| 1.4 | Add lazygit theme to `editors.nix` | MODIFY | 10 min | Low |
| 1.5 | Update `fastfetch.nix` colors | MODIFY | 15 min | Low |
| 1.6 | **Test**: `nh os switch .` — verify starship, lazygit, fastfetch | — | 10 min | — |

### Step 2: Utility Scripts (Phase 2) — Day 2-4

| Order | Task | File | Est. Time | Risk |
|-------|------|------|-----------|------|
| 2.1 | Add battery scripts (5 scripts) | scripts/default.nix | 30 min | Low |
| 2.2 | Add mic-mute script | scripts/default.nix | 10 min | Low |
| 2.3 | Add toggle-gaps script | scripts/default.nix | 10 min | Low |
| 2.4 | Add toggle-layout script | scripts/default.nix | 10 min | Low |
| 2.5 | Add toggle-power-profile script | scripts/default.nix | 10 min | Medium¹ |
| 2.6 | Add screenshot-ocr script | scripts/default.nix | 10 min | Low |
| 2.7 | Add all new scripts to `home/common.nix` package list | MODIFY | 10 min | Low |
| 2.8 | Add `bc`, `tesseract` packages to `home/common.nix` | MODIFY | 2 min | Low |
| 2.9 | Add keybindings to `hyprland.nix` | MODIFY | 15 min | Medium² |
| 2.10 | Fix duplicate mako in `hyprland.nix` exec-once | MODIFY | 2 min | Low |
| 2.11 | **Test**: `nh os switch .` — verify all scripts and keybindings | — | 20 min | — |

¹ `powerprofilesctl` might need the package in systemPackages  
² Keybinding conflicts must be avoided (Super+G, Super+Ctrl+L)

### Step 3: Application Configs (Phase 3) — Day 4-5

| Order | Task | File | Est. Time | Risk |
|-------|------|------|-----------|------|
| 3.1 | Create `helix.nix` | NEW | 15 min | Low |
| 3.2 | Create `mpv.nix` | NEW | 20 min | Medium³ |
| 3.3 | Add both to `flake.nix` imports | MODIFY | 2 min | Low |
| 3.4 | Remove `mpv` from `home/common.nix` packages (mpv module manages it) | MODIFY | 2 min | Medium³ |
| 3.5 | **Test**: `nh os switch .` — verify helix theme, mpv config | — | 10 min | — |

³ Conflicting package management between home.packages and programs.mpv

### Step 4: System Integration (Phase 4) — Day 5-6

| Order | Task | File | Est. Time | Risk |
|-------|------|------|-----------|------|
| 4.1 | Add sysctl + PAM limits to `core.nix` | MODIFY | 5 min | Low |
| 4.2 | Create `snapper.nix` common config | NEW | 10 min | Medium⁴ |
| 4.3 | Add snapper home-only config to `sakura/default.nix` | MODIFY | 10 min | Medium⁴ |
| 4.4 | Add `wiremix` to `home/common.nix` | MODIFY | 2 min | Low |
| 4.5 | **Test**: `nh os switch .` — verify snapper, sysctl, wiremix | — | 20 min | — |

⁴ Snapper requires `.snapshots` subvolume to exist

### Step 5: Waybar Enhancement (Phase 5) — Day 6

| Order | Task | File | Est. Time | Risk |
|-------|------|------|-----------|------|
| 5.1 | Add `custom/power` module to waybar config + CSS | MODIFY | 15 min | Low |
| 5.2 | **Test**: `nh os switch .` — verify waybar shows power profile | — | 5 min | — |

---

## Keybinding Additions Summary

| Binding | Action | Source |
|---------|--------|--------|
| `SUPER SHIFT, B` | Show battery notification | Phase 2.1 |
| `SUPER ALT, G` | Toggle window gaps | Phase 2.4 |
| `SUPER CTRL, M` | Toggle layout (dwindle/master) | Phase 2.5 |
| `SUPER CTRL, PRINT` | Screenshot OCR | Phase 2.7 |

> Existing bindings that might conflict: `SUPER, G` = togglegroup, `SUPER CTRL, L` = lock

---

## Open Questions for User

_No remaining open questions._

---

## Resolved Decisions

| Question | Decision |
|----------|----------|
| Chromium vs Chrome policies | **SKIPPED** — No browser policies needed |
| Hibernation | **NOT FEASIBLE** — LUKS swap (8.8 GiB) far too small for 30 GiB RAM; zram can't be used for hibernate. Would need repartitioning or BTRFS swapfile. Skipped for now. |
| Git/Lazygit extraction | **KEEP in `editors.nix`** — No extraction to separate `git.nix` |
| Starship transient prompts | **ENABLED** — `enableTransience = true` confirmed in starship.nix |
| Snapper scope | **Home only** — no root snapshots configured |
| Keyboard backlight | **SKIPPED** — ThinkPad X13 Gen 1 has no keyboard backlight |