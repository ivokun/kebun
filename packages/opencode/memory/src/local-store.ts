import { PGlite, type Transaction } from "@electric-sql/pglite";
import path from "node:path";
import { collision, MemoryError, SerialQueue, wrongEpoch } from "./errors.js";
import { privateDirectory } from "./files.js";
import {
  canonicalJson, cursorSchema, enforceJsonLimit, MAX_BACKUP_BYTES, MAX_EVENTS, MAX_SYNC_RESPONSE_BYTES,
  memoryBackupSchema, memoryEventSchema, principalSchema, pullResponseSchema, uuidSchema,
  type Cursor, type MemoryBackup, type MemoryEvent, type Principal, type PullResponse,
} from "./protocol.js";

interface MetadataRow {
  account_id: string;
  actor_id: string;
  cursor: unknown;
  sync_epoch: string | null;
  schema_version: number;
}
interface EventRow { event: unknown; canonical: string; }
export interface LocalStatus {
  accountId: string;
  actorId: string;
  durability: "best-effort";
  eventCount: number;
  pendingCount: number;
  cursor: Cursor | null;
  syncEpoch: string | null;
}
interface Mutation<T> { events: readonly MemoryEvent[]; result: T; }

/** Validate the complete backup without opening or changing a destination store. */
function validateBackup(value: unknown, identity: Principal): MemoryEvent[] {
  enforceJsonLimit(value, MAX_BACKUP_BYTES);
  const backup = memoryBackupSchema.parse(value);
  if (backup.accountId !== identity.accountId || backup.actorId !== identity.actorId) {
    throw new MemoryError("identity_mismatch", 409, "Backup belongs to a different device identity.");
  }
  if (backup.cursor && backup.cursor.epoch !== backup.syncEpoch) throw new MemoryError("invalid_request", 400, "Backup cursor is inconsistent.");
  const unique = new Map<string, MemoryEvent>();
  for (const event of backup.events) {
    if (event.accountId !== identity.accountId) throw new MemoryError("identity_mismatch", 409, "Backup contains a foreign account.");
    const previous = unique.get(event.eventId);
    if (previous && canonicalJson(previous) !== canonicalJson(event)) throw collision();
    unique.set(event.eventId, event);
  }
  const pending = new Set(backup.delivery.pendingIds);
  if (pending.size !== backup.delivery.pendingIds.length) throw new MemoryError("invalid_request", 400, "Duplicate delivery metadata.");
  for (const id of pending) {
    if (unique.get(id)?.actorId !== identity.actorId) throw new MemoryError("invalid_request", 400, "Invalid backup delivery metadata.");
  }
  return [...unique.values()];
}

/** Only the daemon opens this database; all access shares one non-reentrant queue. */
export class LocalStore {
  private readonly queue = new SerialQueue();
  private closed = false;
  public readonly accountId: string;
  public readonly actorId: string;

  private constructor(
    private readonly database: PGlite,
    identity: Principal,
    public readonly wasUninitialized: boolean,
  ) {
    this.accountId = identity.accountId;
    this.actorId = identity.actorId;
  }

  static async open(options: { stateDir: string; accountId: string; actorId: string; restore?: unknown }): Promise<LocalStore> {
    const identity = principalSchema.parse({ accountId: options.accountId, actorId: options.actorId });
    const restoreEvents = options.restore === undefined ? undefined : validateBackup(options.restore, identity);
    const stateDir = await privateDirectory(options.stateDir);
    const databaseDir = await privateDirectory(path.join(stateDir, "db"));
    // PGlite 0.5.10 NodeFS fsync/fdatasync are no-ops: local transaction
    // atomicity and normal restart persistence do not guarantee power-loss durability.
    const database = await PGlite.create(databaseDir);
    try {
      return await database.transaction(async (tx) => {
        await tx.exec(`
          CREATE TABLE IF NOT EXISTS memory_meta (
            singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
            schema_version integer NOT NULL CHECK (schema_version = 1),
            account_id uuid NOT NULL, actor_id uuid NOT NULL,
            cursor jsonb, sync_epoch uuid
          );
          CREATE TABLE IF NOT EXISTS memory_events (
            event_id uuid PRIMARY KEY, account_id uuid NOT NULL, actor_id uuid NOT NULL,
            event jsonb NOT NULL, canonical text NOT NULL
          );
          CREATE TABLE IF NOT EXISTS memory_delivery (
            event_id uuid PRIMARY KEY REFERENCES memory_events(event_id), pending boolean NOT NULL
          );
        `);
        const rows = await tx.query<MetadataRow>("SELECT * FROM memory_meta WHERE singleton = true");
        const row = rows.rows[0];
        if (row) {
          if (row.schema_version !== 1 || row.account_id !== identity.accountId || row.actor_id !== identity.actorId) {
            throw new MemoryError("identity_mismatch", 409, "Existing state belongs to a different identity or version.");
          }
          if (restoreEvents !== undefined) throw new MemoryError("restore_requires_empty_state", 409, "Restore requires an uninitialized local store.");
          return new LocalStore(database, identity, false);
        }
        const unbound = await tx.query<{ count: number }>("SELECT count(*)::integer AS count FROM memory_events");
        if (unbound.rows[0]?.count !== 0) throw new MemoryError("invalid_state", 409, "Existing events have no persisted identity.");
        await tx.query("INSERT INTO memory_meta (schema_version, account_id, actor_id) VALUES (1, $1, $2)", [identity.accountId, identity.actorId]);
        const store = new LocalStore(database, identity, true);
        // Identity, restored events and requeued own delivery all commit together;
        // the new store keeps its null cursor/epoch, not the backup's delivery claims.
        if (restoreEvents !== undefined) await store.insertIn(tx, restoreEvents, true);
        return store;
      });
    } catch (error) {
      await database.close();
      throw error;
    }
  }

  private run<T>(operation: (tx: Transaction) => Promise<T>): Promise<T> {
    return this.queue.run(async () => {
      if (this.closed) throw new MemoryError("store_closed", 503, "Local store is closed.");
      return this.database.transaction(operation);
    });
  }

  private async eventsIn(tx: Transaction): Promise<MemoryEvent[]> {
    const result = await tx.query<EventRow>("SELECT event, canonical FROM memory_events ORDER BY event_id");
    return result.rows.map((row) => memoryEventSchema.parse(row.event));
  }

  private async metadataIn(tx: Transaction): Promise<LocalStatus> {
    const result = await tx.query<MetadataRow>("SELECT * FROM memory_meta WHERE singleton = true");
    const row = result.rows[0];
    if (!row) throw new MemoryError("invalid_state", 500, "Local identity metadata is missing.");
    const cursor = cursorSchema.nullable().parse(row.cursor);
    if (cursor && cursor.epoch !== row.sync_epoch) throw new MemoryError("invalid_state", 500, "Local cursor metadata is inconsistent.");
    const count = await tx.query<{ event_count: number; pending_count: number }>(`
      SELECT (SELECT count(*)::integer FROM memory_events) AS event_count,
             (SELECT count(*)::integer FROM memory_delivery WHERE pending) AS pending_count
    `);
    return {
      accountId: this.accountId, actorId: this.actorId,
      durability: "best-effort",
      eventCount: count.rows[0]?.event_count ?? 0, pendingCount: count.rows[0]?.pending_count ?? 0,
      cursor, syncEpoch: row.sync_epoch,
    };
  }

  private async insertIn(tx: Transaction, events: readonly MemoryEvent[], requeueOwn: boolean): Promise<void> {
    for (const event of events) {
      if (event.accountId !== this.accountId) throw new MemoryError("identity_mismatch", 409, "Event belongs to a different account.");
      const canonical = canonicalJson(event);
      const existing = await tx.query<{ canonical: string }>("SELECT canonical FROM memory_events WHERE event_id = $1", [event.eventId]);
      const previous = existing.rows[0];
      if (previous && previous.canonical !== canonical) throw collision();
      if (!previous) {
        await tx.query("INSERT INTO memory_events (event_id, account_id, actor_id, event, canonical) VALUES ($1, $2, $3, $4::jsonb, $5)",
          [event.eventId, event.accountId, event.actorId, JSON.stringify(event), canonical]);
      }
      if (event.actorId === this.actorId && requeueOwn) {
        await tx.query("INSERT INTO memory_delivery (event_id, pending) VALUES ($1, true) ON CONFLICT (event_id) DO UPDATE SET pending = true", [event.eventId]);
      }
    }
  }

  private parseLocal(events: readonly MemoryEvent[]): MemoryEvent[] {
    if (events.length > MAX_EVENTS) throw new MemoryError("payload_too_large", 413, "Too many events in one mutation.");
    enforceJsonLimit(events);
    return events.map((raw) => {
      const event = memoryEventSchema.parse(raw);
      if (event.accountId !== this.accountId || event.actorId !== this.actorId) {
        throw new MemoryError("identity_mismatch", 409, "Local events must belong to this device.");
      }
      return event;
    });
  }

  async appendLocal(events: readonly MemoryEvent[]): Promise<void> {
    const parsed = this.parseLocal(events);
    await this.run((tx) => this.insertIn(tx, parsed, true));
  }

  /** Derivation and append share the same transaction, preventing observed-delete races. */
  async mutate<T>(builder: (events: readonly MemoryEvent[], identity: Principal) => Mutation<T>): Promise<T> {
    return this.run(async (tx) => {
      const mutation = builder(await this.eventsIn(tx), { accountId: this.accountId, actorId: this.actorId });
      await this.insertIn(tx, this.parseLocal(mutation.events), true);
      return mutation.result;
    });
  }

  async readEvents(): Promise<MemoryEvent[]> { return this.run((tx) => this.eventsIn(tx)); }

  async pending(limit = MAX_EVENTS): Promise<MemoryEvent[]> {
    if (!Number.isInteger(limit) || limit < 1 || limit > MAX_EVENTS) throw new MemoryError("invalid_request", 400, "Invalid pending limit.");
    return this.run(async (tx) => {
      const result = await tx.query<EventRow>(`
        SELECT e.event, e.canonical FROM memory_events e
        JOIN memory_delivery d USING (event_id)
        WHERE d.pending AND e.actor_id = $1 ORDER BY e.event_id LIMIT $2`, [this.actorId, limit]);
      return result.rows.map((row) => memoryEventSchema.parse(row.event));
    });
  }

  async acknowledge(ids: readonly string[]): Promise<void> {
    if (ids.length > MAX_EVENTS) throw new MemoryError("invalid_request", 400, "Too many acknowledgement IDs.");
    const parsed = ids.map((id) => uuidSchema.parse(id));
    await this.run(async (tx) => {
      for (const id of parsed) {
        await tx.query(`UPDATE memory_delivery SET pending = false WHERE event_id = $1
          AND EXISTS (SELECT 1 FROM memory_events WHERE event_id = $1 AND actor_id = $2 AND account_id = $3)`,
        [id, this.actorId, this.accountId]);
      }
    });
  }

  /** Reset delivery state only: the immutable local log is never deleted on epoch change. */
  async reconcileEpoch(epoch: string): Promise<void> {
    const parsed = uuidSchema.parse(epoch);
    await this.run(async (tx) => {
      const status = await this.metadataIn(tx);
      if (status.syncEpoch === parsed) return;
      await tx.query("UPDATE memory_meta SET sync_epoch = $1, cursor = NULL WHERE singleton = true", [parsed]);
      await tx.query(`INSERT INTO memory_delivery (event_id, pending)
        SELECT event_id, true FROM memory_events WHERE actor_id = $1 AND account_id = $2
        ON CONFLICT (event_id) DO UPDATE SET pending = true`, [this.actorId, this.accountId]);
    });
  }

  async applyPullPage(value: PullResponse): Promise<void> {
    const page = pullResponseSchema.parse(value);
    enforceJsonLimit(page, MAX_SYNC_RESPONSE_BYTES);
    await this.run(async (tx) => {
      const status = await this.metadataIn(tx);
      if (status.syncEpoch && status.syncEpoch !== page.cursor.epoch) throw wrongEpoch();
      let previous = BigInt(status.cursor?.position ?? "0");
      const seen = new Set<string>();
      for (const entry of page.events) {
        const position = BigInt(entry.position);
        if (position !== previous + 1n || seen.has(entry.event.eventId)) throw new MemoryError("invalid_response", 502, "Invalid pull ordering.");
        previous = position;
        seen.add(entry.event.eventId);
        if (entry.event.accountId !== this.accountId) throw new MemoryError("invalid_response", 502, "Pull contains a foreign account.");
      }
      if (BigInt(page.cursor.position) !== previous || (page.hasMore && page.events.length === 0)) {
        throw new MemoryError("invalid_response", 502, "Pull cursor does not match its committed page.");
      }
      await this.insertIn(tx, page.events.map((entry) => entry.event), false);
      await tx.query("UPDATE memory_meta SET cursor = $1::jsonb, sync_epoch = $2 WHERE singleton = true", [JSON.stringify(page.cursor), page.cursor.epoch]);
    });
  }

  async exportBackup(): Promise<MemoryBackup> {
    return this.run(async (tx) => {
      const status = await this.metadataIn(tx);
      const pending = await tx.query<{ event_id: string }>("SELECT event_id FROM memory_delivery WHERE pending ORDER BY event_id");
      return {
        formatVersion: 1, accountId: this.accountId, actorId: this.actorId,
        events: await this.eventsIn(tx), delivery: { pendingIds: pending.rows.map((row) => row.event_id) },
        cursor: status.cursor, syncEpoch: status.syncEpoch,
      };
    });
  }

  async importBackup(value: unknown): Promise<{ importedCount: number }> {
    const events = validateBackup(value, { accountId: this.accountId, actorId: this.actorId });
    return this.run(async (tx) => {
      const before = (await this.metadataIn(tx)).eventCount;
      await this.insertIn(tx, events, true);
      const after = (await this.metadataIn(tx)).eventCount;
      return { importedCount: after - before };
    });
  }

  async status(): Promise<LocalStatus> { return this.run((tx) => this.metadataIn(tx)); }

  async close(): Promise<void> {
    await this.queue.run(async () => {
      if (this.closed) return;
      this.closed = true;
      await this.database.close();
    });
  }
}
