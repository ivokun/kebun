import { randomUUID } from "node:crypto";
import pg, { type PoolClient } from "pg";
import { collision, MemoryError, wrongEpoch } from "./errors.js";
import {
  canonicalJson, enforceJsonLimit, MAX_SYNC_RESPONSE_BYTES, memoryEventSchema, principalSchema, pullRequestSchema,
  pushRequestSchema, requireProtocol, uuidSchema,
  type Principal, type PullRequest, type PullResponse, type PushRequest, type PushResponse, type ServerInfo,
} from "./protocol.js";

interface EpochRow { epoch: string; schema_version: number; }

/** PostgreSQL 16 store. All objects are confined to the kebun_memory schema. */
export class PostgresServerStore {
  private closing: Promise<void> | undefined;
  private constructor(private readonly pool: pg.Pool) {}

  static async open(databaseUrl: string): Promise<PostgresServerStore> {
    if (!databaseUrl || databaseUrl.includes("\0")) throw new MemoryError("invalid_database_config", 400, "Invalid database configuration.");
    const pool = new pg.Pool({ connectionString: databaseUrl, max: 4, connectionTimeoutMillis: 10_000,
      idleTimeoutMillis: 30_000, statement_timeout: 30_000, application_name: "kebun-memory" });
    // Pool idle-client errors must not become unhandled errors or leak connection details.
    pool.on("error", () => { process.stderr.write("kebun-memory: database connection unavailable\n"); });
    const store = new PostgresServerStore(pool);
    try {
      await store.transaction(async (client) => {
        await client.query("SELECT pg_advisory_xact_lock(1768586869, 1835365487)");
        await client.query(`
          CREATE SCHEMA IF NOT EXISTS kebun_memory;
          CREATE TABLE IF NOT EXISTS kebun_memory.metadata (
            singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
            schema_version integer NOT NULL CHECK (schema_version = 1), epoch uuid NOT NULL
          );
          CREATE TABLE IF NOT EXISTS kebun_memory.feed_heads (
            account_id uuid PRIMARY KEY,
            position numeric(40,0) NOT NULL DEFAULT 0 CHECK (position >= 0)
          );
          CREATE TABLE IF NOT EXISTS kebun_memory.events (
            event_id uuid PRIMARY KEY, account_id uuid NOT NULL, actor_id uuid NOT NULL,
            position numeric(40,0) NOT NULL CHECK (position > 0),
            event jsonb NOT NULL, canonical text NOT NULL,
            UNIQUE (account_id, position)
          );
        `);
        await client.query("INSERT INTO kebun_memory.metadata (schema_version, epoch) VALUES (1, $1) ON CONFLICT (singleton) DO NOTHING", [randomUUID()]);
        await store.epochIn(client);
      });
      return store;
    } catch (error) {
      await pool.end();
      throw error;
    }
  }

  private async transaction<T>(operation: (client: PoolClient) => Promise<T>, snapshot = false): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query(snapshot ? "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY" : "BEGIN");
      const result = await operation(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  private async epochIn(client: PoolClient, lock = false): Promise<string> {
    const result = await client.query<EpochRow>(`SELECT epoch, schema_version FROM kebun_memory.metadata WHERE singleton = true${lock ? " FOR SHARE" : ""}`);
    const row = result.rows[0];
    if (!row || row.schema_version !== 1) throw new MemoryError("unsupported_store_version", 500, "Unsupported server store version.");
    return uuidSchema.parse(row.epoch);
  }

  async info(principal: Principal): Promise<ServerInfo> {
    const identity = principalSchema.parse(principal);
    return this.transaction(async (client) => {
      const epoch = await this.epochIn(client);
      const head = await client.query<{ position: string }>("SELECT position::text FROM kebun_memory.feed_heads WHERE account_id = $1", [identity.accountId]);
      return { protocol: 1, accountId: identity.accountId, epoch, headPosition: head.rows[0]?.position ?? "0" };
    }, true);
  }

  async push(principal: Principal, value: PushRequest): Promise<PushResponse> {
    const identity = principalSchema.parse(principal);
    requireProtocol(value);
    enforceJsonLimit(value);
    const request = pushRequestSchema.parse(value);
    for (const event of request.events) {
      if (event.accountId !== identity.accountId || event.actorId !== identity.actorId) {
        throw new MemoryError("unauthorized", 401, "Events must belong to the authenticated device.");
      }
    }
    return this.transaction(async (client) => {
      const epoch = await this.epochIn(client, true);
      if (request.epoch !== epoch) throw wrongEpoch();
      await client.query("INSERT INTO kebun_memory.feed_heads (account_id) VALUES ($1) ON CONFLICT (account_id) DO NOTHING", [identity.accountId]);
      // Held until COMMIT, including every insert: a later writer cannot publish a
      // cursor ahead of an earlier uncommitted writer. No SQL sequence is used.
      const head = await client.query<{ position: string }>("SELECT position::text FROM kebun_memory.feed_heads WHERE account_id = $1 FOR UPDATE", [identity.accountId]);
      let position = BigInt(head.rows[0]?.position ?? "0");
      const acceptedIds = new Set<string>();
      for (const event of request.events) {
        const canonical = canonicalJson(event);
        const previous = await client.query<{ canonical: string }>("SELECT canonical FROM kebun_memory.events WHERE event_id = $1", [event.eventId]);
        if (previous.rows[0]) {
          if (previous.rows[0].canonical !== canonical) throw collision();
          acceptedIds.add(event.eventId);
          continue;
        }
        const next = position + 1n;
        if (next.toString().length > 40) throw new MemoryError("feed_exhausted", 503, "Feed position limit reached.");
        const inserted = await client.query<{ event_id: string }>(`
          INSERT INTO kebun_memory.events (event_id, account_id, actor_id, position, event, canonical)
          VALUES ($1, $2, $3, $4, $5::jsonb, $6) ON CONFLICT (event_id) DO NOTHING RETURNING event_id`,
        [event.eventId, event.accountId, event.actorId, next.toString(), JSON.stringify(event), canonical]);
        if (inserted.rows.length === 0) {
          // A simultaneous writer for another account can race the global ID key.
          const concurrent = await client.query<{ canonical: string }>("SELECT canonical FROM kebun_memory.events WHERE event_id = $1", [event.eventId]);
          if (concurrent.rows[0]?.canonical !== canonical) throw collision();
        } else {
          position = next;
        }
        acceptedIds.add(event.eventId);
      }
      await client.query("UPDATE kebun_memory.feed_heads SET position = $2 WHERE account_id = $1", [identity.accountId, position.toString()]);
      return { protocol: 1, epoch, acceptedIds: [...acceptedIds] };
    });
  }

  async pull(principal: Principal, value: PullRequest): Promise<PullResponse> {
    const identity = principalSchema.parse(principal);
    requireProtocol(value);
    enforceJsonLimit(value);
    const request = pullRequestSchema.parse(value);
    return this.transaction(async (client) => {
      const epoch = await this.epochIn(client);
      if (request.cursor && request.cursor.epoch !== epoch) throw wrongEpoch();
      const position = request.cursor?.position ?? "0";
      const head = await client.query<{ position: string }>("SELECT position::text FROM kebun_memory.feed_heads WHERE account_id = $1", [identity.accountId]);
      if (BigInt(position) > BigInt(head.rows[0]?.position ?? "0")) {
        throw new MemoryError("invalid_cursor", 400, "Cursor exceeds the committed account feed.");
      }
      const result = await client.query<{ position: string; event: unknown }>(`
        SELECT e.position::text AS position, e.event FROM kebun_memory.events e
        WHERE e.account_id = $1 AND e.position > $2::numeric ORDER BY e.position LIMIT $3`,
      [identity.accountId, position, request.limit + 1]);
      let page: PullResponse = {
        protocol: 1, cursor: { epoch, position }, events: [], hasMore: result.rows.length > 0,
      };
      for (const row of result.rows.slice(0, request.limit)) {
        const events = [...page.events, { position: row.position, event: memoryEventSchema.parse(row.event) }];
        const candidate: PullResponse = {
          protocol: 1, cursor: { epoch, position: row.position }, events, hasMore: result.rows.length > events.length,
        };
        // Measure the exact envelope we return, including JSON escaping and cursor.
        if (Buffer.byteLength(JSON.stringify(candidate), "utf8") > MAX_SYNC_RESPONSE_BYTES) {
          if (page.events.length === 0) throw new MemoryError("payload_too_large", 413, "An event exceeds the synchronization response limit.");
          break;
        }
        page = candidate;
      }
      return page;
    }, true);
  }

  async rotateEpoch(): Promise<string> {
    return this.transaction(async (client) => {
      const epoch = randomUUID();
      await client.query("UPDATE kebun_memory.metadata SET epoch = $1 WHERE singleton = true", [epoch]);
      return epoch;
    });
  }

  async close(): Promise<void> {
    this.closing ??= this.pool.end();
    await this.closing;
  }
}
