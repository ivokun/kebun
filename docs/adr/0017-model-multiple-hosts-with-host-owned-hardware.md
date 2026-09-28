# ADR-0017: Model multiple hosts with a shared host-base aspect and host-owned hardware

- Status: Accepted
- Date: 2026-09-24
- Deciders: Ivokun
- Tags: den, aspects, multi-host, home-manager, hardware

## Context

Kebun has been a single-host flake since ADR-0013: `sakura` is the only
`den.hosts` entry, and a good deal of machine-specific policy lives in
shared modules (`modules/aspects/core.nix` carried sakura's initrd modules,
Renoir kernel parameters and ThinkPad-only `thinkpad_acpi` wiring;
`home/features/hyprland.nix` hard-wired sakura's monitor layout). A second
machine is now being brought under kebun: `ume`, the ASRock B550M-ITX/ac
desktop (Ryzen 9 5900X, RX 9060 XT) that is today the editing host
`ivokun-htpc` running Arch + stock Omarchy. The flake must represent both
hosts without duplicating the workstation policy that already works on
sakura, and without entangling Home Manager in hostname string-matching.

Three modeling questions had to be settled at once:

1. Where does shared NixOS policy live so both hosts inherit it?
2. How do host-specific facts (laptop vs desktop, greeter layout, monitor
   layout) reach Home Manager modules without `hostName` conditionals?
3. Where do machine facts (disk layout, LUKS UUIDs) live, given that ume's
   disk configuration is currently a **pre-install snapshot** of the live
   Arch system, not a verified post-install state?

## Decision

### 1. A reusable `host-base` aspect

`modules/aspects.nix` defines `den.aspects.host-base`, included by every
host aspect. It carries:

- the `den.batteries.hostname` include (`networking.hostName` from the
  entity declaration),
- `_module.args.inputs`,
- shared `home-manager.useUserPackages` / `backupFileExtension`,
- the flake-wide overlays (deno test-skip, OpenCode),
- and the `kebun.host` option tree (below).

Host aspects (`sakura`, `ume`) then compose
`host-base + core + desktop + dev + networking + printing + snapper +
shell-entry` and import only `hosts/<name>/`.

### 2. Machine-specific policy moves out of shared aspects; capability options connect Home Manager

Anything inherently machine-bound left the shared aspects:

- `core.nix` no longer pins initrd/kernel modules or sakura's Renoir
  kernel parameters — these are per-host in `hosts/<name>/default.nix`.
- The shared system now models **workstation policy**, not one machine:
  `dev.nix` gained rootless Docker (moved from hosts/sakura), and
  `networking.nix` gained the shared `/mnt/tubeinas` NFS automount. The export
  uses its LAN address; remote access depends on a separately configured
  Tailscale subnet route.

What varies in *behavior* rather than *hardware* is expressed as typed
**capability options** in `host-base`:

```nix
options.kebun.host = {
  isLaptop     = lib.mkOption { type = lib.types.bool;   default = false; };
  greeterLayout= lib.mkOption { type = lib.types.str;    default = "us";  };
  monitorsLua  = lib.mkOption { type = lib.types.lines; default = "";    };
};
```

Hosts set them in `hosts/<name>/default.nix` (sakura: `isLaptop = true`,
`greeterLayout = "jp"`, X13 panel layout; ume: `isLaptop = false`, `us`,
RX 9060 XT dual-monitor layout). Home Manager consumes them through
**`osConfig`**, not hostname matching:

- `home/features/hyprland.nix` branches on
  `osConfig.kebun.host.isLaptop` for battery/lid/touchpad config and
  renders `osConfig.kebun.host.monitorsLua` into `monitors.lua`.
- `home/common.nix` gates the laptop-only scripts on `isLaptop`.
- `modules/aspects/desktop.nix` interpolates `kebun.host.greeterLayout`
  into the SDDM greeter config.

This is deliberately *why there are no hostname conditionals in HM*: the
`osConfig` path keeps the homeManager class host-independent (modules
continue to evaluate where `osConfig` is absent through defaulted module
arguments and `or`-defaults), keeps each host's facts in
`hosts/<name>/` as data, and extends to a third host by declaring one new
entity — no edits to `home/**` and no `hostName == "ume"` strings to hunt
down later. The options are typed and defaulted so a forgotten declaration
is a build-time-visible (or clearly-defaulted) situation, not a silent
nil-interpolation.

### 3. Host-owned hardware facts in `hosts/<name>/`

Machine facts stay in `hosts/<name>/`: hardware-configuration (fileSystems,
LUKS UUIDs, swap), GPU/Bluetooth/kernel modules, TPM2 enrollment targets,
stateVersion. Shared workstation policy (aspects) and machine facts
(hosts/) are cleanly separated — `hosts/ume/default.nix` contains only
ume-specific policy and hardware details.

`ume` is declared as: ASRock B550M-ITX/ac, Ryzen 9 5900X (Vermeer), Radeon
RX 9060 XT (Navi 44, amdgpu + 32-bit mesa for Steam), B550 firmware set,
Intel AC 3168 Wi-Fi/BT, Steam + xpadneo, TPM2 LUKS auto-unlock on the
existing `root` mapper. Its `hosts/ume/hardware-configuration.nix` records
the **current** ivokun-htpc disk layout (LUKS2 → Btrfs `@`/`@home`/`@log`,
ESP `17FE-CA36`, Btrfs swapfile `/swap/swapfile`, ext4 media disk at
`/mnt/entertainments`) — a pre-install snapshot, banner-pinned with
regeneration instructions, since the pending kebun install may re-partition
and change UUIDs/subvolume/mapper facts.

### 4. Sakura behavior preservation is the gate

Restructuring shared modules risks regressions on the deployed host. The
gate for this change is that `nix build
.#nixosConfigurations.sakura.config.system.build.toplevel` remains green
and the sakura activation diff stays semantically neutral: aspects that
split policy out must re-provide it per-host so sakura's evaluated
configuration is equivalent.

## Consequences

### Positive

- Adding a third host is: one `hosts/<name>/` tree, one aspect block
  wiring shared aspects + the host files, one `den.hosts` entry.
- No `hostName` conditionals in Home Manager — capability options are
  self-documenting at the host level and keep consumer branches based on
  behavior rather than machine identity.
- Shared workstation policy is single-sourced (Docker, NFS, snapper) and
  can no longer drift between hosts.
- Machine facts read without context: `hosts/<name>/` contains only that
  machine.

### Negative

- The `kebun.host` surface grows as more laptop/desktop/driver variance
  appears (e.g. power-key behavior, idle policy) — there is a risk of it
  re-growing into an implicit machine description. Capabilities should
  stay coarse (few booleans, strings, or Lua blocks), not become per-machine
  tunables.
- `osConfig` access is untyped at the consumer (`or`-fallbacks); a typo of
  `osConfig.kebun` paths is a silent default, not a build error.

### Neutral

- ume's hardware-configuration is knowingly a snapshot until install
  regenerates it; INSTALL-UME.md makes regeneration an explicit gate
  rather than an assumption.
- Sakura stays the deployed reference; ume activation happens only on the
  matching target machine.

## References

- ADR-0013 — Den adoption (aspect wiring this extends)
- INSTALL-UME.md — ume runbook (pre-install constraints, decision gates)
- `modules/aspects.nix` — `host-base` and the `kebun.host` options
- `hosts/sakura/`, `hosts/ume/` — machine facts

## Notes

- Date proposed: 2026-09-24
- Date accepted: 2026-09-24
- Proposed by: Ivokun
- Accepted by: Ivokun
