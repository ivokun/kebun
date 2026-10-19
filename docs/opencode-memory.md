# OpenCode memory

## Rollout boundary

The v1 design is accepted in [ADR-0019](adr/0019-use-local-first-curated-opencode-memory.md).
Kebun initially enables **local memory only**. Remote synchronization is an
explicit later opt-in, not an existing endpoint or a deployment claim. The
server rollout gates live in Pasal's `docs/memory-sync.md`; none is waived by
building the client package.

## Ownership and data flow

```text
OpenCode sessions → MCP stdio adapters → private Unix socket
                                            ↓
                              one user daemon / one PGlite owner
                                            ↓
                               file-backed event log + outbox
                                            ↓ optional HTTPS
                            Pasal sync server → PostgreSQL
```

- Kebun owns the shared TypeScript application and protocol in
  `packages/opencode/memory/`, packaged by `packages/opencode/memory.nix`.
  The exported `kebun-memory` / `kebun-memory-server` artifacts serve the
  workstation and server roles without a second implementation in Pasal.
  Pasal consumes only an explicit, published immutable package pin; remote
  deployment has its own enablement gates.
- Home Manager owns the user service and configuration, **not database
  contents**. Only the daemon opens PGlite. Each OpenCode connection starts
  `kebun-memory mcp-stdio --socket ABS`; adapters never open the data directory.
- The daemon holds a nonblocking kernel `flock` for its lifetime. A second
  owner exits 75. State is mode 0700 and the socket is mode 0600 in a private
  runtime directory. Preserve the lock file; an occupied socket is an error,
  not permission to unlink it or take over another process's state.
- Local mutations atomically append events and pending-delivery metadata.
  Missing credentials, an unreachable server, or a protocol error must not
  prevent local reads/writes or discard pending events. Synchronization is
  bounded, serialized, retryable background work, not a write dependency.

### Accepted local persistence limit

The operator explicitly chose **best-effort PGlite**, retaining the file-backed
backend rather than adding a journal or switching to SQLite. PGlite 0.5.10's
NodeFS does not implement effective host `fsync`/`fdatasync`. PostgreSQL
`fsync=on` or PGlite `relaxedDurability: false` therefore cannot provide a
power-loss guarantee through this backend.

State persists across normal, orderly restarts, and local transactions keep
events and outbox metadata atomic. **A successful local acknowledgement is not
a power-loss durability guarantee:** acknowledged writes/outbox entries may be
lost or corrupted after sudden power failure. There is **no guaranteed bounded
loss window**; the sync polling interval is not one. Local status reports
`"durability": "best-effort"`, and the daemon emits one warning at startup;
these disclose the limitation, not detect or repair storage damage.

Once remote sync is deployed, orbit001 can protect only events already uploaded
and committed there, not locally acknowledged work that never reached it.
Consistent exports and verified independent backups remain separate recovery
measures. Neither replication nor this storage choice replaces them.

## Curated, scoped memory

The [memory policy](../home/opencode/prompts/memory-policy.md) defines what to
remember. The parent agent curates durable, verified facts; subagents return
candidate facts to the parent and have all memory mutators denied in the
managed OpenCode configuration. Recall can be delegated. These permissions
are an agent workflow boundary, not isolation from another process with the
same Unix uid.
“Durable facts” means lasting relevance here, not guaranteed I/O durability.

Every tool requires a `scope`: `project:`, `topic:`, or `user:` followed by a
stable lowercase identifier (at most 128 characters altogether). Use scoped
`search_nodes` / `open_nodes` instead of retrieving the entire graph. Scope
separates relevance; it is **not a remote authorization boundary** within an
account. Keep credentials, raw transcripts, and speculative conclusions out
of memory. Verify recalled facts against their current source before acting.

The familiar tools remain: `create_entities`, `create_relations`,
`add_observations`, `delete_entities`, `delete_relations`,
`delete_observations`, `read_graph`, `search_nodes`, and `open_nodes`.
Mutations also require `provenance = {source: string, verifiedAt: UTC_ISO,
revision?: string}`. `remember({scope, name, entityType, text, provenance,
supersedes?: UUID[]})` atomically ensures an entity and adds an assertion or
correction. Creating an existing entity is a no-op; use `remember` or
`add_observations` to add facts.

Events have immutable UUID identities and carry account, actor, scope, and
provenance. Corrections name superseded assertion IDs; deletions retract
currently observed additions. Concurrent corrections remain visible as
conflicts. Wall-clock timestamps do not pick a winner. Retractions suppress
their targets even when those targets arrive later; they do not erase the
retained event log, other replicas, or backups.

An observed entity deletion can leave an unseen concurrent observation active.
Search/open results therefore expose matching `assertions` even when no entity
declaration survives. Inspect assertion IDs and conflicts as well as `entities`;
an empty entity list does not necessarily mean that no matching knowledge exists.

## Identity

These UUIDs are public identifiers, not credentials:

| Identity | UUID |
|---|---|
| Account | `6f67358f-8bbf-48d1-a48f-ec40c3c3fd8d` |
| ume actor | `efe55bc9-fa10-4af0-b29b-217338fe7508` |
| sakura actor | `90241cd7-cf71-4927-8ff4-62ecb02ffdca` |

`kebun.host.memoryAccountId` and `kebun.host.memoryActorId` are typed host
capabilities passed to HM through `osConfig`, never selected by hostname
conditionals in a home module.
Persisted account/actor identity must match configuration; a mismatch fails
closed. Retain both IDs through reinstalls and restores. Retire the previous
writer before giving its actor identity to a replacement machine. A different
host uses its own actor, not a copy of the first host's database directory.

## Build and local operation

Build the package or either host closure without activating anything:

```bash
nix build .#kebun-memory
nix build .#nixosConfigurations.ume.config.system.build.toplevel
# Or use the sakura output. Activation is ON the matching machine only:
# nh os switch .
```

`home/features/opencode-memory.nix` installs the package and the
`kebun-memory.service` user unit, wanted by `default.target` rather than the
graphical session. Its state is `~/.local/state/kebun-memory`; its socket is
`$XDG_RUNTIME_DIR/kebun-memory/memory.sock`, not a project-local file. After an
authorized matching-host switch, reload OpenCode's managed configuration and
check local status. A successful build alone does not verify runtime ownership,
permissions, or readiness.

Paths must be absolute and normalized; socket and export destinations require
real, existing parent directories. For the managed defaults:

```bash
SOCKET="${XDG_RUNTIME_DIR:?}/kebun-memory/memory.sock"
systemctl --user status kebun-memory.service
kebun-memory status --socket "$SOCKET"

install -d -m 0700 "$HOME/Documents/backups/opencode-memory"
kebun-memory export --socket "$SOCKET" \
  --output "$HOME/Documents/backups/opencode-memory/memory-$(date -u +%Y%m%dT%H%M%SZ).json"

# Only a validated v1 backup of this SAME account and actor:
kebun-memory import --socket "$SOCKET" \
  --input '/absolute/path/to/memory-backup.json'
```

| Command | Result and safety contract |
|---|---|
| `status --socket ABS` | Prints JSON with account/actor IDs, `eventCount`, `pendingCount`, pull `cursor`, `syncEpoch`, `durability: "best-effort"`, and sanitized `sync` status. A backlog while offline is expected. |
| `export --socket ABS --output ABS` | Consistent transaction snapshot of the complete versioned backup; exclusively creates a new mode-0600 file. Refuses an existing destination; success exits 0 without printing the backup. |
| `import --socket ABS --input ABS` | Fully validates then atomically unions events; rejects foreign identity and conflicting immutable IDs. Preserves current identity/cursor/epoch and requeues imported own events. Prints JSON with `importedCount`; never replaces state. |

Exports contain `formatVersion: 1`, identity, the complete event log, delivery
metadata, and cursor/epoch, but **no credentials**. They still contain private
facts: protect and encrypt off-machine copies. An import can restore historical
assertions; review the source and intended union before running it.
The current backup file/transport limit is 64 MiB; oversized history fails
rather than silently truncating.

### Legacy JSONL is a separate migration

Before switching away from `mcp-server-memory`, explicitly discover its real
storage location from the resolved old MCP command, environment (including any
`MEMORY_FILE_PATH`), working directory, and the installed server's default.
Do not guess a path from this checkout or assume an empty graph means no data.
Export the old graph with the old server and retain a protected copy of the
original JSONL before disabling it. Do not run competing writers while making
that copy.

The v1 `import` command accepts the **versioned backup above, not legacy
JSONL**. There is no promised JSONL converter. An explicit, reviewed conversion
must assign scopes, provenance, identity, and event IDs before a legacy import
can be supported. Neither activation nor startup may overwrite, delete, or
silently migrate the discovered legacy file. Keep it until a migration and
restore have actually been verified.

## Backup, recovery, and upgrades

**Sync is not backup.** Replication also distributes mistakes and retractions.
Make independent consistent exports and test restoring them into isolated,
fresh state with synchronization disabled. Do not copy/synchronize a live
PGlite directory, raw database files, or a PostgreSQL data directory with a
file-sync tool.

ume has a scheduled on-site home Borg job (ADR-0018); sakura has no scheduled
backup yet. Put consistent exports in a non-excluded location and verify their
actual inclusion and restoration from an archive. Backing up the live home
directory is not proof that its running PGlite files form a recoverable
snapshot. No scheduled memory-specific export or successful restore is implied
by this guide.

### Restore a lost local store

1. Stop the managed daemon and its adapters. Preserve any surviving state and
   pending events; do not reset or delete a store to cure a sync error.
2. Choose a fresh, uninitialized state directory and a private runtime
   directory. Confirm the backup's account and actor match the retired/lost
   writer. A ume backup is not a sakura import.
3. Start one foreground daemon, initially without remote sync:

   ```bash
   install -d -m 0700 '/absolute/path/to/private-runtime'
   kebun-memory daemon \
     --state-dir '/absolute/path/to/fresh-state' \
     --socket '/absolute/path/to/private-runtime/memory.sock' \
     --account-id '<SAVED_ACCOUNT_UUID>' --actor-id '<SAVED_ACTOR_UUID>' \
     --restore '/absolute/path/to/memory-backup.json'
   ```

4. Inspect `status`, scoped recall, and a new export. `--restore` is only for
   uninitialized state: it retains event/identity IDs, requeues the actor's
   events, and starts with null pull cursor and sync epoch. It remains a
   foreground daemon until stopped, not a one-shot restore command. If restore
   fails after initialization, preserve that directory and diagnose the input;
   use another fresh directory for a corrected attempt. Arrange the managed
   service to use the recovered state after stopping the foreground owner; remove any
   one-time restore flag before normal restarts. Re-enable sync only after
   identity and contents are confirmed.

Export before an application/storage upgrade and retain the previous artifact
and backup. A Nix generation rollback does not reverse a data migration.
Unsupported formats fail closed; v1 makes **no data downgrade guarantee**.

### Server restore / epoch change

Pasal must restore PostgreSQL with ingress paused and deliberately rotate the
persisted epoch before clients reconnect. On a changed epoch the client keeps
its entire log and pending state, clears its pull cursor, and requeues **all
of its own events**, including previously acknowledged events. It then
reconciles idempotently. A push acknowledgement never advances the pull cursor.
Clients retain other actors' events but cannot upload them under their own
credentials; complete recovery needs the server backup and/or each actor's
surviving store/export. Never hand-edit cursors or manufacture an epoch reset.

## Later remote enrollment

Wait for Pasal's artifact pin, PostgreSQL authentication/inventory, private
tailnet/ACL, device registry, and backup/restore gates. The host opt-in is
`kebun.host.memorySync`: `enable`, `enrollmentConfirmed`, `url` (HTTPS), and
`tokenFile` (absolute runtime string path). Both booleans default to false;
confirmation records operator completion, not automated enrollment. HM passes
`--sync-url` and `--token-file` only when enabled. The token is read at each
sync cycle. Tokens belong in runtime secret files, never the repository, Nix
store, command arguments, or memory records. ume uses
sops-nix; sakura's missing host recipient must be obtained and enrolled, not
invented to make an opt-in evaluate.

The private remote API is **not MCP**: only the daemon talks to it. It uses
authenticated `/v1/sync/info`, `/v1/sync/push`, and `/v1/sync/pull` routes and
protocol version 1. Server feed positions are transactional committed
decimal-string cursors, not timestamps or independently allocated sequence IDs.
Identical event IDs and content are retry-safe; a differing immutable payload
is a conflict, not an overwrite. Invalid responses must leave local data/cursors
untouched.

Pull pages are also bounded by their complete serialized UTF-8 size (2 MiB),
not just event count. Their positions must be contiguous from the saved cursor;
the cursor advances only through included events.

To revoke a device, remove its registry hash and restart the server,
revoke tailnet access as needed, and rotate affected credentials. Revocation
blocks future remote access; it **cannot erase offline replicas or backups**.
