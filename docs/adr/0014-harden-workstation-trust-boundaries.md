# ADR-0014: Harden Workstation Trust Boundaries

- Status: Accepted
- Date: 2026-09-21
- Deciders: Ivokun
- Tags: security, nixos, ssh, docker, nfs, users

## Context

The working tree accumulated several trust-boundary compromises that were
convenient during bring-up but are not appropriate for a workstation whose
threat model is "anyone with physical or LAN access to the machine":

- **A declaratively known password.** The reusable plaintext bootstrap
  password was present in the Nix source and copied into the Nix store on
  every install.
- **Password-based SSH** open to more than the trusted network.
- **LocalSend/mDNS** exposure not scoped to physical links.
- **Membership in unnecessary supplementary groups** — `audio`, `video`,
  `input`, `storage`, `docker` — each of which grants device or daemon
  access well beyond what the desktop session needs (systemd-logind and the
  seat session already provide the needed access).
- **Nix `trusted-users`** included `@wheel`. The Nix manual treats trusted
  daemon clients as effectively root because they may use privileged daemon
  options and import unsigned store paths.
- **Rootful Docker** with the user in the `docker` group — the socket is
  root-equivalent.
- **A writable NFS export** mounted with default mount flags, i.e. suid
  binaries and device nodes from the network.

Two deployment facts frame the decision: the current editing host is
IVOKUN-HTPC (the reference machine, where these changes were implemented
and could be sanity-evaluated), but the target is **sakura** — all runtime
validation must occur on sakura. Nothing here has been deployed yet.

## Decision

1. **Password: declarative → interactive.** Remove the declarative known
   password entirely; set the password interactively after `nixos-install`
   and before first boot. No reusable password or hash in the repo.
2. **SSH: key-only, Tailscale-scoped.** Authorize the ivokun-htpc Ed25519
   public key for `ivokun`; disable password authentication. Restrict the
   firewall's SSH port to `tailscale0` — SSH is reachable only over
   Tailscale, never on the physical LAN.
3. **LAN services scoped to physical links.** LocalSend and mDNS
   (network discovery, which are only meaningful with machines on the same
   physical network) are firewalled to the physical interfaces, not
   Tailscale.
4. **Group hygiene.** Remove `audio`, `video`, `input`, `storage`, and
   `docker` from the user's supplementary groups — systemd-logind's seat
   session grants device access to the active user, and the remaining
   memberships only widen the blast radius. Keep `wheel` (administrative
   elevation is the point of the account) and `kvm` (needed by Claude
   Desktop Cowork's QEMU VM) with explicit reasons documented in the config.
5. **Nix `trusted-users = [ "root" ]`.** The user builds via the daemon
   like any unprivileged client; no user-supplied store paths can be
   activated without root.
6. **Docker: rootless.** Move Docker to rootless mode (user
   `ivokun`). The `docker` group membership is gone with rootful mode; the
   user talks to its own user-scoped daemon, not a root-equivalent socket.
7. **NFS: hardened flags + ordering.** The writable export is mounted with
   `nosuid,nodev,noexec` so suid binaries and device nodes cannot arrive
   over NFS, and the mount unit is ordered after `tailscaled` so
   mount-time hangs degrade predictably when the network is not yet up.

The working tree already implements all of the above. This ADR records
the decision; deployment and runtime validation are still pending on
sakura.

Deliberately **out of scope**: no Secure Boot or verified-boot claim is
made — ADR-0010's TPM2 convenience unlock remains unchanged. OpenCode
supply-chain and credential-environment changes are recorded separately in
ADR-0015.

## Consequences

### Positive

- No reusable password secret in the repo; fresh installs get a password
  that was never committed anywhere.
- SSH exposure shrinks to the Tailscale interface; the physical LAN sees
  no SSH at all.
- Docker compromise no longer implies root; NFS cannot import suid or
  device-node payloads.
- Group memberships match the desktop threat model (wheel + kvm only),
  which is auditable at a glance.

### Negative

- **Rootless Docker has separate state and socket.** Images, containers,
  and volumes under rootful Docker are not visible to the rootless daemon
  (and vice versa); tooling must talk to `$XDG_RUNTIME_DIR/docker.sock`, and any
  existing rootful state needs explicit migration or re-pull.
- **SSH depends on Tailscale.** If `tailscaled` is down, misconfigured,
  or the tailnet is unreachable, there is no SSH path — physical console
  access becomes mandatory for remote recovery.
- Fresh-install password setup is a manual step; a forgotten `passwd`
  leaves the account locked.
- Unprivileged `nix` commands cannot add ad-hoc substituters or trusted keys;
  caches must be reviewed and declared system-wide.
- NFS `noexec` means binaries legitimately served over NFS cannot be
  executed directly (only data/docs belong there in practice).

### Neutral

- LocalSend/mDNS on physical links only matches how those protocols are
  actually used; nothing meaningful is lost by excluding Tailscale.
- The current host (IVOKUN-HTPC) is the reference machine and not
  kebun-managed for runtime purposes; the changes take effect when sakura
  rebuilds, and all runtime validation (SSH over Tailscale, rootless
  Docker, NFS mount flags, group removals) must happen there.

## References

- ADR-0010 — TPM2 LUKS unlock and single SDDM prompt (boot trust story, unchanged here)
- ADR-0013 — Den framework; the aspect layout these hardening changes live in
- ADR-0015 — reproducible OpenCode extensions and reduced credential exposure
- `man systemd-logind` — seat/device access for the active session
- Docker docs — rootless mode state and socket locations

## Notes

- Date proposed: 2026-09-21
- Date accepted: 2026-09-21
- Proposed by: Ivokun
- Accepted by: Ivokun
