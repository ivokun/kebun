# ADR-0002: Use Standalone iwd Instead of NetworkManager for WiFi Management

## Status

Accepted

## Context

The system originally used NetworkManager with iwd as its WiFi backend (`networking.networkmanager.wifi.backend = "iwd"`). This setup caused impala (the WiFi TUI) to fail with "Operation failed" errors when attempting to connect to networks.

The root cause: when NetworkManager uses iwd as its WiFi backend, NetworkManager owns the connection lifecycle. It tells iwd when to connect/disconnect based on NM connection profiles. When impala sends D-Bus commands directly to iwd, NetworkManager detects the unexpected state change and overrides it, causing the connection attempt to fail. This is an architectural conflict — two managers fighting over WiFi state.

impala's documentation explicitly states:

> To avoid conflicts, ensure wireless management services like NetworkManager or wpa_supplicant are disabled.

Additionally, the NixOS NetworkManager module automatically enables `networking.wireless.iwd.enable = true` when `wifi.backend = "iwd"` is set, so adding it explicitly was redundant (correcting a previous suggestion).

## Decision

Replace NetworkManager with standalone iwd for WiFi management. Use systemd-networkd for wired/Ethernet DHCP (previously handled by NetworkManager).

### Configuration changes

1. **`hosts/common/networking.nix`**: `networkmanager.enable = false`, `wireless.iwd.enable = true` with IPv6 settings, `useNetworkd = true`, and `systemd.network` rules for wired/wireless DHCP
2. **`hosts/common/users.nix`**: Remove `networkmanager` group — iwd D-Bus policies grant access to the `wheel` group (user is already a member)
3. **`home/features/hyprland.nix`**: Replace `nm-connection-editor` keybinding with `launch-wifi` (impala)
4. **`packages/scripts/default.nix`**: Replace `nm-connection-editor` in hardware menu with `launch-wifi`
5. **`INSTALL.md`**: Replace `nmcli` commands with `iwctl` equivalents

## Consequences

### Positive

- **impala works correctly**: iwd runs standalone, no conflict with a secondary connection manager
- **Simpler WiFi stack**: iwd is smaller and faster than NetworkManager; fewer moving parts for WiFi
- **Cleaner D-Bus**: Single owner of WiFi state (iwd) instead of two competing managers
- **Consistent UX**: impala TUI for WiFi, `iwctl` as CLI fallback — both talk to iwd directly

### Negative

- **Lost NetworkManager features**: No VPN integration via NM applets, no shared connections, no automatic profile switching by SSID
- **Manual WiFi management**: Users must use impala or `iwctl` — no GUI WiFi applet in the system tray
- **Ethernet DHCP via systemd-networkd**: Slightly different behavior from NetworkManager for wired connections; requires explicit `.network` files
- **Migration risk**: First rebuild requires reconnecting to WiFi via `iwctl` since NM will be disabled before iwd has stored network profiles
- **Waybar network module**: Still works (uses libnl), but may show slightly different information without NM as backend

### Neutral

- **Tailscale unaffected**: Operates independently as a userspace daemon
- **DNS unaffected**: `systemd-resolved` continues to handle DNS resolution
- **`iwctl` CLI still available**: `iwd` package in home-manager provides the CLI tool
- **Firewall unaffected**: NixOS firewall rules remain the same

## References

- [impala README — Prerequisites](https://github.com/pythops/impala) ("ensure wireless management services like NetworkManager are disabled")
- [NixOS iwd module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/iwd.nix)
- [NixOS NetworkManager module — auto-enables iwd](https://github.com/NixOS/nixpkgs/pull/68147)
- [iwd DefaultInterface quirk](https://github.com/NixOS/nixpkgs/pull/141877)
- ADR-0001 (original system architecture using NetworkManager)

## Notes

- Date proposed: 2026-05-18
- Date accepted: 2026-05-18
- Proposed by: ivokun (user reported impala connection failures)
- Accepted by: ivokun