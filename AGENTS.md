# AGENTS.md — Kebun

NixOS system flake for a single host (`sakura`, ThinkPad X13 Gen 1). Not a dev project — no tests, CI, or build pipeline. Changes apply via system rebuild.

## Rebuild commands

```bash
# Standard rebuild (uses nh, installed by the flake)
nh os switch .

# Alternative without nh
sudo nixos-rebuild switch --flake .#sakura

# First build or when unfree packages fail
sudo NIXPKGS_ALLOW_UNFREE=1 nixos-rebuild switch --flake .#sakura --impure
```

## Emergency recovery

If `nix.conf` gets corrupted with broken placeholder keys (happens after bad rebuilds), run:

```bash
./fix-and-rebuild.sh
```

This fixes `trusted-public-keys` and rebuilds.

## Structure

```
flake.nix              # Entry point. One system: sakura. Formatter: alejandra.
hosts/common/          # Shared NixOS modules
hosts/sakura/          # Host-specific NixOS config + hardware-configuration.nix
home/common.nix        # Shared home-manager packages & settings
home/sakura.nix        # Host-specific home settings (monitor layout, borg excludes)
home/features/         # Modular home-manager configs (hyprland, waybar, shell, etc.)
packages/scripts/      # Custom scripts packaged as Nix derivations
```

## Key conventions

- **Swap is intentionally NOT in `hosts/common/`**. It lives in `hardware-configuration.nix` to avoid merge conflicts. Do not add `swapDevices` to common modules.
- **Home Manager backup extension**: `hm-backup`. Existing dotfiles are backed up on first activation.
- **Formatter**: `nix fmt` runs `alejandra`.
- **Flake inputs**: `nixpkgs` (nixos-unstable), `home-manager` (master), `hyprland`, `nh`, `walker`, `nix-index-database`.
- **No dynamic theming**: Rose Pine Dawn is hardcoded across Hyprland, Waybar, Mako, SwayOSD, etc. Theme changes require editing Nix expressions and rebuilding.

## Hardware quirks

- AMD Renoir APU (`amdgpu`)
- LUKS2 with TPM2 auto-unlock (`crypttabExtraOpts` has `tpm2-device=auto`)
- zram swap primary (50%, zstd), fallback swapfile in BTRFS `@swap`
- Multi-monitor layout defined in `home/sakura.nix` (HDMI-A-1, DP-2)
- NFS automount to `192.168.100.29:/mnt/tank/ivokun` via Tailscale

## Gotchas

- **UWSM is required** for Hyprland autostart. All `exec` bindings and `exec-once` entries use `uwsm app -- <command>`. Raw `exec` without UWSM breaks systemd integration.
- **Deno override**: `flake.nix` skips a flaky Deno test (`uv_compat::tests::tty_reset_mode_restores_termios`). Do not remove without checking if the test still fails.
- **Waybar toggle**: Use `toggle-waybar` script (systemd-based), not `pkill waybar`. Waybar runs as a systemd user service in this setup.
- **Home-manager state version**: `25.05`. Do not bump without reading upstream migration notes.

## Where things are configured

| Concern | File |
|---------|------|
| System packages & boot | `hosts/common/core.nix` |
| Hyprland, fonts, input method, Walker | `hosts/common/desktop.nix` |
| Networking, Tailscale, SSH, firewall | `hosts/common/networking.nix` |
| User account, groups, zsh | `hosts/common/users.nix` |
| Dev tools (gcc, go, node, postgres, etc.) | `hosts/common/dev.nix` |
| Hyprland keybindings, hypridle, hyprlock, mako | `home/features/hyprland.nix` |
| Waybar style & modules | `home/features/waybar.nix` |
| Custom scripts (screenshot, toggle-waybar, etc.) | `packages/scripts/default.nix` |
| Shell (zsh, starship, atuin, etc.) | `home/features/shell.nix` |
| Terminals (alacritty, ghostty, kitty) | `home/features/terminals.nix`, `ghostty.nix`, `kitty.nix` |
| Editors (neovim) | `home/features/editors.nix` |
| Theme (Rose Pine Dawn) | `home/features/theme-rose-pine.nix` |

## Docs

- `INSTALL.md` — Full NixOS installation guide (LUKS + BTRFS + flakes)
- `OMARCHY_DISCREPANCY_REPORT.md` — Analysis of what was ported from Omarchy (Arch) to NixOS
- `docs/adr/` — Architecture decision records
