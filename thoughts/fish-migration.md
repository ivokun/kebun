# Migrate sakura Host Shell from Zsh to Fish

## TL;DR

Replace zsh with fish as the primary interactive shell on the sakura host. Fish provides built-in autosuggestions, syntax highlighting, and superior completions — eliminating the need for oh-my-zsh, zsh-autosuggestions, and zsh-syntax-highlighting. Zsh config is preserved as a working fallback shell.

## Context

- **Original Request**: "Move from zsh to fish for sakura host shell"
- **Interview Decisions**:
  - Keep zsh as fallback (both shell configs coexist)
  - Keep Starship as prompt (switch integration from zsh to fish)
  - Add `fish-abbreviation-tips` plugin (replaces `zsh-you-should-use`)
  - Drop `cd()` override (Starship already shows directory)
  - Move Hyprland TTY1 autostart to fish `loginShellInit`
- **Key Observations**:
  - All custom scripts in `packages/scripts/` use POSIX sh — **no changes needed**
  - Fish has built-in autosuggestions & syntax highlighting — **3 of 4 zsh plugins become unnecessary**
  - No `.zshrc` or `.zsh` files in repo — zsh config is 100% home-manager managed
  - All terminal emulators hardcode `${pkgs.zsh}/bin/zsh` — must update
  - `oh-my-zsh` git plugin → replace with `fishPlugins.git-abbr` (in nixpkgs)

## Work Objectives

Fish is the default login shell. When the user opens any terminal or logs in on TTY1:
1. Fish starts with full configuration (prompt, completions, abbreviations, functions)
2. Starship prompt works identically to current zsh setup
3. Atuin, zoxide, direnv, fzf integrations work in fish
4. Hyprland auto-starts on TTY1 login
5. All custom shell functions (zd, open, compress, iso2sd, web2app, web2app-remove, refresh-xcompose) work in fish
6. Running `zsh` manually still works as a fallback
7. mise (language version manager) activates in fish

## Execution Strategy

### Wave 1: System & Core Config (sequential — system then home-manager)

| # | Task | Depends On | SubAgent |
|---|------|------------|----------|
| 1 | Add fish to system config (users.nix) | — | @backend-architect |
| 2 | Create fish.nix feature file | — | @backend-architect |
| 3 | Update shell.nix — add fish integrations | — | @backend-architect |

### Wave 2: Terminal & Editor Updates (parallel)

| # | Task | Depends On | SubAgent |
|---|------|------------|----------|
| 4 | Update terminals.nix — Alacritty → fish | Wave 1 | @backend-architect |
| 5 | Update ghostty.nix — shell integration → fish | Wave 1 | @backend-architect |
| 6 | Update kitty.nix — shell → fish | Wave 1 | @backend-architect |
| 7 | Update editors.nix — tmux default-shell → fish | Wave 1 | @backend-architect |

### Wave 3: Wire Up & Verify

| # | Task | Depends On | SubAgent |
|---|------|------------|----------|
| 8 | Add fish.nix import to flake.nix | Wave 1 | @backend-architect |
| 9 | Format with alejandra | Waves 1-2 | — |
| 10 | Rebuild and verify | Wave 3 | @bug-hunter |

---

## Detailed TODOs

### Task 1: Add fish to system config (`hosts/common/users.nix`)

- **What to do**: Set fish as login shell, enable fish system-wide, keep zsh enabled
- **Must NOT do**: Remove zsh entirely, remove `programs.zsh.enable`
- **SubAgent Profile**: @backend-architect
- **Parallelization**: Can run with Tasks 2-3
- **References**: Current `hosts/common/users.nix`
- **Acceptance Criteria**: `users.users.ivokun.shell` points to `pkgs.fish`, both `programs.fish.enable` and `programs.zsh.enable` are `true`

**Exact changes to `hosts/common/users.nix`:**

```nix
# Before:
shell = pkgs.zsh;
# After:
shell = pkgs.fish;

# Before:
programs.zsh.enable = true;
# After:
programs.fish.enable = true;
programs.zsh.enable = true;  # Keep as fallback
```

---

### Task 2: Create fish feature file (`home/features/fish.nix`)

- **What to do**: Create a new Nix file with complete fish configuration
- **Must NOT do**: Remove or modify `shell.nix` zsh config, add the `cd()` override, reference zsh paths
- **SubAgent Profile**: @backend-architect
- **Parallelization**: Can run with Tasks 1, 3
- **References**: Current `home/features/shell.nix` (lines 1-237)
- **Acceptance Criteria**: All zsh functions have fish equivalents, Starship/Atuin/Zoxide/Direnv/FZF have fish integrations enabled, Hyprland autostart works, abbreviations match current aliases, abbreviation-tips plugin is sourced

**Full content for `home/features/fish.nix`:**

```nix
{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  programs.fish = {
    enable = true;

    # Use abbreviations instead of aliases (abbreviation-tips friendly)
    preferAbbrs = true;

    # Generate completions from man pages
    generateCompletions = true;

    # ─── Environment Variables ───
    shellInit = ''
      set -gx LANG en_US.UTF-8
      set -gx LC_CTYPE en_US.UTF-8
      set -gx LC_ALL en_US.UTF-8
      set -gx TERM xterm-256color
      set -gx TERMINAL alacritty
      set -gx EDITOR nvim
      set -gx SUDO_EDITOR $EDITOR
    '';

    # ─── Hyprland Auto-start on TTY1 Login ───
    loginShellInit = ''
      if test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = "1"
        exec uwsm start hyprland-uwsm.desktop
      end
    '';

    # ─── Interactive Shell Setup (mise activation, abbreviation-tips) ───
    interactiveShellInit = ''
      # Activate mise (language version manager)
      if command -v mise &>/dev/null
        mise activate fish | source
      end

      # Disable fish greeting
      set -g fish_greeting
    '';

    # ─── Abbreviations ───
    # These replace zsh aliases. Abbreviations auto-expand when typed.
    shellAbbrs = {
      # Editor
      vim = "nvim";
      vi = "nvim";

      # Listing (fully expanded — avoids chained abbreviation issues)
      ls = "eza -lh --group-directories-first --icons=auto";
      lsa = "eza -lha --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --long --icons --git";
      lta = "eza --tree --level=2 --long --icons --git -a";

      # Fuzzy finder
      ff = "fzf --preview 'bat --style=numbers --color=always {}'";

      # Archive
      decompress = "tar -xzf";

      # Git abbreviations (replace oh-my-zsh git plugin)
      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit -v";
      gcmsg = "git commit -m";
      gd = "git diff";
      gds = "git diff --staged";
      gco = "git checkout";
      gcb = "git checkout -b";
      gp = "git push";
      gpll = "git pull";
      gst = "git status";
      glog = "git log --oneline --decorate --graph";
      gw = "git switch";
    };

    # ─── Custom Functions ───
    functions = {
      # Zoxide interactive with pwd display
      zd = {
        description = "Zoxide interactive directory jump";
        body = ''
              if test (count $argv) -eq 0
                set -l dir (zoxide query --interactive)
                and cd $dir
              else
                zoxide $argv
              end
              echo "📍 $PWD"
            '';
      };

      # xdg-open wrapper
      open = {
        description = "Open file/URL with default application";
        body = "xdg-open $argv &>/dev/null &; disown";
      };

      # Compress files
      compress = {
        description = "Compress files/directories into tar.gz";
        argumentNames = ["files"];
        body = "tar -czf $argv[1].tar.gz $argv";
      };

      # Write ISO to SD card
      iso2sd = {
        description = "Write ISO image to block device";
        body = ''
              if test (count $argv) -lt 2
                echo "Usage: iso2sd <iso-file> <device>"
                return 1
              end
              sudo dd if=$argv[1] of=$argv[2] bs=4M status=progress conv=fsync
            '';
      };

      # Create webapp desktop entry
      web2app = {
        description = "Create a webapp .desktop file";
        body = ''
              if test (count $argv) -lt 2
                echo "Usage: web2app <name> <url> [icon]"
                return 1
              end
              mkdir -p ~/.local/share/applications
              echo "[Desktop Entry]
              Name=$argv[1]
              Exec=brave --app=\"$argv[2]\"
              Type=Application
              Icon=$argv[3]
              Categories=Network;WebBrowser;" > ~/.local/share/applications/$argv[1].desktop
              echo "Created ~/.local/share/applications/$argv[1].desktop"
            '';
      };

      # Remove webapp desktop entry
      web2app-remove = {
        description = "Remove a webapp .desktop file";
        body = ''
              if test (count $argv) -lt 1
                echo "Usage: web2app-remove <name>"
                return 1
              end
              rm -f ~/.local/share/applications/$argv[1].desktop
              echo "Removed ~/.local/share/applications/$argv[1].desktop"
            '';
      };

      # Restart fcitx5 for XCompose changes
      refresh-xcompose = {
        description = "Restart fcitx5 input method";
        body = "fcitx5 -r &; disown";
      };
    };

    # ─── Plugins ───
    plugins = [
      {
        name = "abbreviation-tips";
        src = pkgs.fetchFromGitHub {
          owner = "ryota-murakami";
          repo = "fish-abbreviation-tips";
          rev = "v1.0.0";  # VERIFY: check GitHub for latest release tag
          sha256 = "0000000000000000000000000000000000000000000000000";  # UPDATE: replace with actual hash after first build attempt
        };
      }
    ];
  };

  # ─── Starship Prompt ───
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    # NOTE: settings are defined in shell.nix — they apply globally
    # No need to duplicate here; just enable the fish integration.
    # However, since shell.nix also enables starship with enableZshIntegration,
    # both integrations can coexist. starship.enable is idempotent.
  };

  # ─── Atuin (Shell History Sync) ───
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    # NOTE: settings defined in shell.nix apply globally
  };

  # ─── Zoxide (Smart cd) ───
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # ─── Direnv (Per-directory env) ───
  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    nix-direnv.enable = true;
  };

  # ─── FZF (Fuzzy Finder) ───
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };
}
```

**IMPORTANT NOTES for the implementer:**

1. **`fish-abbreviation-tips` sha256**: The `sha256` value above is a placeholder. On first build, Nix will fail and print the correct hash. Replace the placeholder with that hash. Alternative: use `lib.fakeSha256` or `lib.fakeHash` to get the correct hash from the error message.

2. **Starship/Atuin/Direnv/Zoxide/FZF settings**: These programs are already enabled in `shell.nix` with `enableZshIntegration = true`. Adding `enableFishIntegration = true` in `fish.nix` is safe because home-manager merges these — the `enable` flag is idempotent, and both integration flags can coexist. **However**, there's a cleaner alternative: add `enableFishIntegration = true` directly in `shell.nix` to each program alongside the existing `enableZshIntegration`. This keeps all tool configurations in one place. See Task 3.

3. **Git abbreviations**: The `g*` abbreviations above are the most common ones from oh-my-zsh's git plugin. If the user wants the full set, `fishPlugins.git-abbr` can be added to `home.packages` (it provides abbreviations via a fish plugin). For now, a curated subset is included inline.

4. **The `lsa` abbreviation**: Fully expanded to `eza -lha ... -a` rather than `'ls -a'` because abbreviations don't chain-expand. Similarly `lta` is fully expanded.

---

### Task 3: Update shell integrations in `home/features/shell.nix`

- **What to do**: Add `enableFishIntegration = true` to all tools that support it, keeping `enableZshIntegration = true` for fallback
- **Must NOT do**: Remove any zsh configuration, change any settings
- **SubAgent Profile**: @backend-architect
- **Parallelization**: Can run with Tasks 1-2
- **References**: Current `home/features/shell.nix`
- **Acceptance Criteria**: All five tools have both `enableZshIntegration` and `enableFishIntegration` set to `true`

**Changes to `home/features/shell.nix`:**

Add `enableFishIntegration = true` to each program:

```nix
# Line 131: starship
programs.starship = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;   # ← ADD
  # ... settings unchanged ...
};

# Line 159: atuin
programs.atuin = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;   # ← ADD
  # ... settings unchanged ...
};

# Line 172: zoxide
programs.zoxide = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;   # ← ADD
};

# Line 176: direnv
programs.direnv = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;   # ← ADD
  nix-direnv.enable = true;
};

# Line 183: fzf
programs.fzf = {
  enable = true;
  enableZshIntegration = true;
  enableFishIntegration = true;   # ← ADD
};
```

**IMPORTANT**: If you chose the approach in Task 2 where `fish.nix` defines its own `programs.starship.enable = true` etc., you'll get a merge conflict because `enable = true` would be set in both files. The **recommended approach** is:
- Remove the `programs.starship`, `programs.atuin`, `programs.zoxide`, `programs.direnv`, `programs.fzf` blocks from `fish.nix`
- Only add `enableFishIntegration = true` in `shell.nix` for each tool

This keeps all tool configuration centralized in `shell.nix`.

**Revised `fish.nix`**: The programs block at the bottom of Task 2's `fish.nix` should be REMOVED. Instead, only `shell.nix` defines these tools with both integration flags.

---

### Task 4: Update Alacritty (`home/features/terminals.nix`)

- **What to do**: Change shell program from zsh to fish
- **Must NOT do**: Remove `args = ["-l"]` — fish also supports `-l` for login shell
- **Acceptance Criteria**: Alacritty launches fish as login shell

**Change on line 28-31:**

```nix
# Before:
terminal.shell = {
  program = "${pkgs.zsh}/bin/zsh";
  args = ["-l"];
};

# After:
terminal.shell = {
  program = "${pkgs.fish}/bin/fish";
  args = ["-l"];
};
```

---

### Task 5: Update Ghostty (`home/features/ghostty.nix`)

- **What to do**: Change shell integration from zsh to fish, update command
- **Must NOT do**: Change any other settings (colors, font, window, etc.)
- **Acceptance Criteria**: Ghostty launches fish with proper shell integration

**Changes on lines 48-49:**

```nix
# Before:
shell-integration = "zsh";
command = "${pkgs.zsh}/bin/zsh -l";

# After:
shell-integration = "fish";
command = "${pkgs.fish}/bin/fish -l";
```

---

### Task 6: Update Kitty (`home/features/kitty.nix`)

- **What to do**: Change shell command from zsh to fish
- **Must NOT do**: Change any other settings
- **Acceptance Criteria**: Kitty launches fish as login shell

**Change on line 51:**

```nix
# Before:
shell = "${pkgs.zsh}/bin/zsh -l";

# After:
shell = "${pkgs.fish}/bin/fish -l";
```

---

### Task 7: Update tmux in editors (`home/features/editors.nix`)

- **What to do**: Change tmux default-shell from zsh to fish
- **Must NOT do**: Change any other tmux settings
- **Acceptance Criteria**: New tmux sessions use fish

**Change on line 81:**

```nix
# Before:
set-option -g default-shell ${pkgs.zsh}/bin/zsh

# After:
set-option -g default-shell ${pkgs.fish}/bin/fish
```

---

### Task 8: Add fish.nix import to `flake.nix`

- **What to do**: Add `./home/features/fish.nix` to the home-manager module imports
- **Must NOT do**: Remove `./home/features/shell.nix` — it's still needed for zsh fallback
- **Acceptance Criteria**: fish.nix is imported after shell.nix

**Change in `flake.nix`, inside `mkHomeManagerModules` (around line 72):**

```nix
imports = [
  ./home/common.nix
  ./home/sakura.nix
  ./home/features/hyprland.nix
  ./home/features/waybar.nix
  ./home/features/terminals.nix
  ./home/features/shell.nix
  ./home/features/fish.nix        # ← ADD (after shell.nix)
  ./home/features/editors.nix
  ./home/features/theme-rose-pine.nix
  ./home/features/fcitx5.nix
  ./home/features/btop.nix
  ./home/features/fastfetch.nix
  ./home/features/ghostty.nix
  ./home/features/kitty.nix
];
```

---

### Task 9: Format with alejandra

- **What to do**: Run `nix fmt` to format all changed files
- **Must NOT do**: Skip this step
- **Acceptance Criteria**: `nix fmt` succeeds with no errors

```bash
nix fmt
```

---

### Task 10: Rebuild and verify

- **What to do**: Build the NixOS configuration and test
- **Must NOT do**: Skip verification steps
- **Acceptance Criteria**: Build succeeds, fish is default shell, all integrations work

**Rebuild command:**
```bash
nh os switch .
```

**Verification checklist:**

| Check | Command | Expected |
|-------|---------|----------|
| Fish is default shell | `echo $SHELL` | `/run/current-system/sw/bin/fish` |
| Starship prompt shows | Visual check | Rose-pine styled `>` prompt with directory + git branch |
| Atuin works | Press `Ctrl+R` | Atuin search appears |
| Zoxide works | `zd` | Interactive zoxide search |
| Direnv works | Enter a nix project dir | `direnv: loading` message |
| FZF works | Press `Ctrl+T` | Fuzzy file finder appears |
| Abbreviations expand | Type `ls` + Space | Expands to `eza -lh --group-directories-first --icons=auto` |
| env vars set | `echo $EDITOR` | `nvim` |
| Hyprland starts on TTY1 | Log in on TTY1 | Hyprland launches |
| Mise activates | `mise --version` | Works |
| Functions work | `zd`, `open .`, `compress test` | All function correctly |
| Zsh fallback | Run `zsh` | Zsh works with all integrations |

---

## Dependency Matrix

| Task | Depends On | Blocks |
|------|------------|--------|
| Task 1 (users.nix) | — | Task 10 |
| Task 2 (fish.nix) | — | Task 8, Task 10 |
| Task 3 (shell.nix) | — | Task 10 |
| Task 4 (terminals.nix) | — | Task 10 |
| Task 5 (ghostty.nix) | — | Task 10 |
| Task 6 (kitty.nix) | — | Task 10 |
| Task 7 (editors.nix) | — | Task 10 |
| Task 8 (flake.nix) | Task 2 | Task 10 |
| Task 9 (format) | All file changes | Task 10 |
| Task 10 (rebuild) | Tasks 1-9 | — |

## Files Changed Summary

| File | Action | Scope |
|------|--------|-------|
| `home/features/fish.nix` | **CREATE** | New fish configuration (programs.fish, functions, abbreviations, plugins) |
| `home/features/shell.nix` | **MODIFY** | Add `enableFishIntegration = true` to 5 programs |
| `hosts/common/users.nix` | **MODIFY** | Change `shell = pkgs.fish`, add `programs.fish.enable = true` |
| `home/features/terminals.nix` | **MODIFY** | Change Alacritty shell program to fish |
| `home/features/ghostty.nix` | **MODIFY** | Change shell-integration and command to fish |
| `home/features/kitty.nix` | **MODIFY** | Change shell to fish |
| `home/features/editors.nix` | **MODIFY** | Change tmux default-shell to fish |
| `flake.nix` | **MODIFY** | Add `./home/features/fish.nix` to imports |

## Rollback Strategy

If anything goes wrong, a NixOS rollback is straightforward:

```bash
# Roll back to previous generation
sudo nixos-rebuild switch --rollback

# Or use nh
nh os switch --rollback
```

The zsh configuration remains intact and functional as a fallback. To temporarily switch back:

```bash
# Change login shell back to zsh
chsh -s $(which zsh)
```

## Important Notes for Implementer

### fish-abbreviation-tips Plugin Hash

The `sha256` in `fish.nix` is a placeholder (`0000...`). After the first build attempt, Nix will fail with an error message containing the correct hash. Replace the placeholder with that hash.

**Alternative approach**: Use `pkgs.lib.fakeHash` or `pkgs.lib.fakeSha256` as the placeholder — Nix will error with the correct hash.

**If the GitHub repo URL is wrong**: Search GitHub for `fish-abbreviation-tips` and update the `owner`/`repo`/`rev` accordingly. The tag `v1.0.0` may not exist — check the releases page for the latest tag.

### Programs: fish.nix vs shell.nix

**Recommended approach**: Keep all tool configuration (starship, atuin, zoxide, direnv, fzf) in `shell.nix`. Only add `enableFishIntegration = true` there. The `fish.nix` file should only contain `programs.fish` configuration and `home.file` resources (like the `.config/fish` files).

This avoids merge conflicts from having `programs.starship.enable = true` in two files.

### Git Abbreviations

The git abbreviations in `fish.nix` are a curated subset of oh-my-zsh's git plugin. If the user wants the full set, add `fishPlugins.git-abbr` to `home.packages` in `common.nix` — it provides comprehensive git abbreviations as a fish plugin.

### Fish Shell Differences to Be Aware Of

1. **No `&&` in commands**: Fish uses `; and` instead of `&&`. But in Nix config, `shellInit` etc. are fish syntax, so this is handled.
2. **No `export`**: Fish uses `set -gx` instead of `export`.
3. **No command substitution `$()`**: Fish uses `()` for command substitution.
4. **No `~/.zshrc`**: Fish uses `~/.config/fish/config.fish` (managed by home-manager).
5. **No `alias` needed**: Fish abbreviations (`abbr`) auto-expand visually, making them more discoverable.
6. **Function syntax**: `function name ... end` instead of `name() { ... }`.

## Success Criteria

- [ ] `home/features/fish.nix` created with complete fish configuration
- [ ] `home/features/shell.nix` has `enableFishIntegration = true` on all 5 tools
- [ ] `hosts/common/users.nix` sets fish as login shell, keeps zsh enabled
- [ ] All 4 terminal configs point to fish
- [ ] `flake.nix` imports `fish.nix`
- [ ] `nix fmt` succeeds
- [ ] `nh os switch .` succeeds
- [ ] Fish is the default shell (`echo $SHELL` → fish)
- [ ] Starship prompt works in fish
- [ ] Atuin, zoxide, direnv, fzf integrations work in fish
- [ ] All custom functions work (zd, open, compress, iso2sd, web2app, refresh-xcompose)
- [ ] Hyprland auto-starts on TTY1
- [ `zsh` still works as fallback
- [ ] abbreviation-tips plugin shows abbreviation suggestions
