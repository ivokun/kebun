# ADR-0012: Derive the Network Panel's Connection State From Script Data Under iwd

## Status

Accepted

## Context

ADR-0002 keeps kebun on standalone iwd plus systemd-networkd
(`networkmanager.enable = false`), while Omarchy v4.0.2 assumes NetworkManager
throughout. That divergence surfaced in the shell's network panel: it showed
"NOT CONNECTED" with a disconnected glyph even on a live Wi-Fi link.

Root cause: Quickshell's `Networking` module implements only a NetworkManager
backend — its `NetworkBackendType` enum is `["None", "NetworkManager"]`
(verified in quickshell 0.3.0's qmltypes). With no NM daemon, `Networking.devices`
is empty, and the vendored panel (`shell/plugins/panels/network/Panel.qml`)
derives its connection `kind` from those devices and networks, so every kebun
session reads as disconnected. The panel's numeric stats were never wrong —
ping, IP, gateway and throughput come from the `omarchy-network-status
--verbose` script (ip/iw/ping/jq based, NM-free). The panel lied about state
while telling the truth about numbers.

A second defect compounded it: `iw` was not resolvable on the session PATH, so
`omarchy-network-status` could not report SSID, signal or frequency at all —
the script layer was incomplete too.

## Decision

Apply ADR-0009's pattern — verbatim upstream content, patched at build time.
`packages/omarchy/patches/network-iwd-state.patch` is applied in
`packages/omarchy/default.nix` after the shebang rewrite and before
`wrapProgram` (`pkgs.patch` joins `nativeBuildInputs`). On kebun, the
`omarchy-network-status --verbose` stream becomes the single source of truth
for connection state; the stock NetworkManager branch is retained verbatim for
a possible future NM.

### 1. `Model.js`: dBm → percent conversion

`signalPercentFromDbm(dbm)` maps dBm onto the 0–100 percent scale the wifi
glyphs expect — `clamp(2 * (dbm + 100), 0, 100)`, `-1` for non-numeric input
(classic wireless-tools mapping: -100 dBm → 0, -50 dBm and hotter → 100).
Exported alongside `wifiIconFor`.

### 2. `Panel.qml`: script-data fallback for state

Five edits, each marked `// Kebun (iwd)`:

- `kind`: the stock device-based logic moves under
  `if (networkManagerAvailable)`; without NM it falls back to the script data —
  `info.type === "wifi" / "ethernet"` (info carries a type only while a
  default route exists)
- `signalStrength`: for wifi without NM, falls back to
  `Model.signalPercentFromDbm(info.signal_dbm)`
- `canDisconnect`: additionally true when NM is absent and `info.type` is set —
  gates the hero phrase vs "NOT CONNECTED" (purely display state)
- hero icon `opacity`: constant 1.0 (was 0.5 to flag "no NetworkManager"; the
  icon now reflects live state, and the dim state would be permanent on kebun)
- `detailsPoll` timer: `running: true` always, `interval` 1500ms open /
  5000ms closed (was open-only 1500ms). With no NM there are no state-change
  signals, so bar icon, hero SSID and kind track a 5s background poll while
  the panel is closed.

### 3. Dependencies and wrapping (`packages/omarchy/default.nix`)

- `runtimeDeps` gains `iw`, `iproute2`, `iputils` (jq was already there)
- `omarchy-network-status` joins `wrappedScripts`, so its iw/ip/ping/jq calls
  resolve from the closure PATH instead of the session PATH

Verification: `nixos-rebuild build --flake .#sakura` passes; the patched env
emits `ssid KAMISAMA`, `signal_dbm -46`, `freq 5180.0` from
`omarchy-network-status --verbose`; a node test of `Model.js` maps -46 dBm →
100% → the strongest wifi glyph; qmllint reports no syntax errors.

## Consequences

### Positive

- The bar icon and panel hero now reflect the live link — kind, SSID and
  signal strength populate instead of a permanent "NOT CONNECTED"
- No fork: the patch lives in-tree and re-applies on env bumps; the NM branch
  is untouched, so the panel keeps working if kebun ever runs NM

### Negative

- Panel-side Wi-Fi actions remain unavailable without NM: scan/connect/forget
  (needs an iwd backend in Quickshell or nmcli), the QR share
  (`omarchy-network-qr` reads the PSK via nmcli), band pinning
  (`omarchy-network-band` sets bands via nmcli — its read path returns nothing
  without NM, so the section stays hidden) and the DNS provider *setter* pills
  (`omarchy-dns` write path needs root + NM; its *read* path is NM-free and
  works, falling back to `/etc/systemd/resolved.conf`). Use impala or iwctl.
- The closed-panel poll is permanent: one extra `omarchy-network-status
  --verbose` sample every 5s (two ~1s-budget pings + ip + iw reads) —
  negligible CPU, but always on
- Upstream bumps must re-apply the patch; if the context drifts, regenerate it

### Neutral

- "NOT CONNECTED" can still appear — legitimately, when no default route is
  up (info carries a type only while the route exists)
- The `canDisconnect` widening is display state only; there is no disconnect
  action behind it without NM

## References

- ADR-0002 (standalone iwd), ADR-0009 (build-time patch pattern)
- `packages/omarchy/patches/network-iwd-state.patch`,
  `packages/omarchy/default.nix`
- Upstream: omacom/omarchy v4.0.2 (rev `346e69e`),
  `shell/plugins/panels/network/`
- quickshell 0.3.0 qmltypes — `NetworkBackendType` = ["None", "NetworkManager"]
- `docs/omarchy-parity-backlog.md` (§6 NetworkManager migration; item 17)

## Notes

- Date proposed: 2026-09-06
- Date accepted: 2026-09-06
- Proposed by: ivokun + agent session
- Accepted by: ivokun
- Operational note: after a live switch, Hyprland's own environment still
  carries the previous generation's `OMARCHY_PATH`, so keybind-spawned shell
  IPC targets a dead config path until re-login. For the in-session case, set
  it without restarting: `hyprctl eval "hl.env('OMARCHY_PATH', '<new-env>')"`
  (verified on sakura), or just re-login.
