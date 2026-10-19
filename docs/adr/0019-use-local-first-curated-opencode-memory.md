# ADR-0019: Use Local-First Curated OpenCode Memory

- Status: Accepted (architecture; remote deployment gated)
- Date: 2026-10-19

## Context

Multiple OpenCode sessions and two workstations need long-lived, relevant recall
without racing JSONL writers or depending on a VPS for every tool call. Sharing
a raw database directory would couple database ownership to file replication;
timestamp-based overwrite would silently lose concurrent corrections. Memory
also needs an explicit curator rather than accumulating every subagent's
intermediate conclusions.

## Decision

- **Kebun owns one application/protocol.** The shared source in
  `packages/opencode/memory/` produces the `kebun-memory` and server artifacts.
  Pasal owns hosting and later consumes an explicit immutable published
  package; it does not fork the application or depend on a local Kebun path.
- **One local owner, many adapters.** A Home Manager user daemon exclusively
  owns PGlite under a lifetime kernel lock. MCP stdio adapters use its private
  Unix socket. Local reads and atomic event/outbox writes remain available
  without a network or token; HM manages configuration, not database contents.
- **Accept best-effort PGlite persistence.** After explanation, the operator
  chose to retain PGlite rather than add a journal or switch to SQLite.
  PGlite 0.5.10 NodeFS has no effective host `fsync`/`fdatasync`; `fsync=on` and
  `relaxedDurability: false` do not establish a power-loss guarantee. File
  persistence across normal restarts and transactional event/outbox writes
  remain, but successfully acknowledged local writes can be lost or corrupted
  after sudden power failure, with no guaranteed bounded loss window. Status
  declares `durability: "best-effort"` and the daemon warns once at startup.
- **Scoped, curated assertions.** Every tool requires scope; writes require
  provenance. The parent agent curates facts and managed subagents have memory
  mutators denied. UUID-addressed immutable additions, corrections, and
  retractions produce a deterministic graph with explicit concurrent conflicts,
  not generic last-write-wins. Scope is relevance isolation, not an account ACL.
- **Replicate events, not database files.** Each workstation retains its own
  stable actor within one account. Optional HTTPS synchronization reaches a
  loopback-only PostgreSQL-backed server through private Tailscale ingress.
  Per-device hashed bearer credentials bind writes to account/actor. Feed
  positions and acknowledgements follow transaction commit; timestamps do not
  determine order.
- **Preserve state on failure.** Retries and pulls never discard pending data.
  A restored server deliberately changes its persisted epoch; clients retain
  their logs, clear pull cursors, and requeue their own events. Versioned,
  consistent exports and independent backups are recovery inputs, not raw
  directory sync. Import is validated union, not replacement. Legacy JSONL
  requires explicit discovery/export and a separately reviewed conversion.
- **Stage deployment.** Enable local operation first. Remote opt-in waits for
  a published artifact pin, runtime hashed registry, tailnet enrollment/ACLs,
  live PostgreSQL inventory and removal of Pasal's `local all all trust`, and
  verified logical backups/Borg inclusion/restore. No endpoint or successful
  deployment is asserted by this decision.

## Consequences

Offline work and multiple sessions no longer require multiple database owners.
The event log preserves provenance and concurrency, at the cost of unbounded
v1 history and more operational machinery than a JSON file. Retractions and
credential revocation cannot erase offline copies or old backups. Parent-only
MCP writes are a workflow control, not a sandbox against the same Unix user.

The best-effort local acknowledgement is an accepted storage limitation, not a
weaker standard for curating verified facts. Once deployed, orbit001 protects
only events already uploaded and committed, not unsent local work.
Synchronization is not backup: ume's home Borg job needs verified consistent
exports; sakura still needs an independent backup plan. Upgrades need a
pre-upgrade export and restore procedure; a Nix rollback promises no storage
downgrade. Pasal's existing PostgreSQL local trust rule is a real isolation
blocker even with a dedicated application role.

## References

- [Operations and recovery](../opencode-memory.md)
- [ADR-0014: Workstation trust boundaries](0014-harden-workstation-trust-boundaries.md)
- [ADR-0018: Borg and sops-nix](0018-schedule-borg-backups-with-sops-nix-secrets.md)
- Shared wire schemas: `packages/opencode/memory/src/protocol.ts`
- Pasal: `docs/memory-sync.md` and `docs/adr/2026-10-19-private-memory-sync.md`
