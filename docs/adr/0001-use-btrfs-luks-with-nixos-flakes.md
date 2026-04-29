# ADR-0001: Use NixOS with BTRFS, LUKS, and Flakes for Desktop Configuration

## Status

Accepted

## Context

We need to replace an existing Arch Linux installation running Omarchy (an opinionated Arch-based Hyprland distribution) with a reproducible, declarative NixOS setup. The existing system has:

- BTRFS filesystem with LUKS encryption
- Hyprland window manager with extensive customizations
- Custom `omarchy-*` shell scripts for theme switching and system management
- Japanese input (fcitx5 + Mozc)
- Multi-monitor setup (2560x1440@60Hz primary)
- AMD RX 9060 XT GPU
- 32GB RAM

Key requirements:
1. Full disk encryption must be preserved
2. BTRFS snapshot capability should be maintained
3. The new system must be reproducible across machines
4. The extensive Omarchy desktop configuration must be replicated
5. Theme switching (currently dynamic via shell scripts) needs a NixOS-appropriate solution

## Decision

We will use NixOS unstable with Flakes and Home Manager, configured as a multi-machine flake repository named "kebun" (Indonesian for "garden"). The system will use:

1. **NixOS unstable** — Rolling release matching the Arch experience
2. **BTRFS + LUKS** — Preserve existing encryption and snapshot capability
3. **Flakes** — Reproducible builds with locked inputs
4. **Home Manager** — Declarative user configuration
5. **Hyprland with UWSM** — Wayland compositor with systemd integration
6. **Minimal Omarchy replacement** — Replace dynamic shell scripts with static Nix configs rather than replicating the full omarchy ecosystem

### BTRFS Subvolume Layout

| Subvolume | Mount Point | Purpose |
|-----------|-------------|---------|
| `@` | `/` | Root filesystem |
| `@home` | `/home` | User home directories |
| `@nix` | `/nix` | Nix store (grows large) |
| `@log` | `/var/log` | System logs |
| `@swap` | `/swap` | Swapfile location |

### Hostname

`sakura` — chosen to match the "kebun" (garden) theme.

## Consequences

### Positive

- **Reproducibility**: The entire system is declared in Git and can be rebuilt identically on any machine
- **Rollback safety**: NixOS generations + BTRFS snapshots provide multiple recovery paths
- **Atomic upgrades**: System changes are atomic — failed builds don't leave the system in a broken state
- **Multi-machine ready**: The flake structure supports adding new hosts with shared modules
- **No imperative drift**: Unlike Arch where `pacman -S` changes the system imperatively, NixOS changes only through config

### Negative

- **Theme switching is slower**: Dynamic theme changes (Omarchy's `omarchy-theme-set`) require a Nix rebuild instead of instant symlink swapping
- **Learning curve**: Nix language and flake concepts have a steep learning curve
- **Binary cache limitations**: Some packages (especially from AUR) may not be in nixpkgs and need custom derivations
- **Disk space**: Nix store duplicates packages across generations until garbage collected

### Neutral

- **Shell scripts replaced**: Custom `omarchy-*` commands are replaced with Nix packages or direct keybindings
- **Package management**: `nix-shell` / `nix develop` replaces `pacman -S` for temporary tool needs
- **Update workflow**: `nh os switch .` replaces `omarchy-update`

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Hyprland Wiki](https://wiki.hyprland.org/)
- [MADR Format](https://adr.github.io/madr/)
- Current Arch system: Omarchy 3.3.3

## Notes

- Date proposed: 2026-04-29
- Date accepted: 2026-04-29
- Proposed by: ivokun (user-initiated migration)
- Accepted by: ivokun
