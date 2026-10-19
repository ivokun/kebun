import { chmod, lstat } from "node:fs/promises";
import { type Server } from "node:http";
import { MemoryError, publicError } from "./errors.js";
import { absolutePath, hasFsCode, readBoundedFile, safeParent } from "./files.js";
import { callRequestSchema, jsonServer, readJson, sendJson } from "./http.js";
import { LocalStore } from "./local-store.js";
import { MemoryService, readOnlyTools } from "./memory-service.js";
import { MAX_BACKUP_BYTES, MAX_PUSH_BYTES } from "./protocol.js";
import { syncBaseUrl, syncOnce } from "./sync.js";

export interface SyncStatus {
  enabled: boolean;
  running: boolean;
  lastAttemptAt: string | null;
  lastSuccessAt: string | null;
  nextAttemptAt: string | null;
  lastError: { code: string; message: string } | null;
}

class SyncWorker {
  private timer: NodeJS.Timeout | undefined;
  private pass: Promise<void> | undefined;
  private readonly controller = new AbortController();
  private stopped = false;
  private dirty = false;
  private failures = 0;
  private readonly state: SyncStatus;

  constructor(private readonly store: LocalStore, private readonly options: { url: string; tokenFile: string } | undefined,
    private readonly pollSeconds: number) {
    this.state = { enabled: options !== undefined, running: false, lastAttemptAt: null, lastSuccessAt: null,
      nextAttemptAt: null, lastError: null };
  }

  status(): SyncStatus {
    return { ...this.state, lastError: this.state.lastError ? { ...this.state.lastError } : null };
  }

  trigger(): void {
    if (!this.options || this.stopped) return;
    this.dirty = true;
    if (this.pass || (this.timer && this.failures > 0)) return;
    this.schedule(0);
  }

  private schedule(seconds: number): void {
    if (this.stopped || !this.options) return;
    if (this.timer) clearTimeout(this.timer);
    this.state.nextAttemptAt = new Date(Date.now() + seconds * 1000).toISOString();
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.pass = this.run().finally(() => { this.pass = undefined; });
    }, seconds * 1000);
  }

  private async run(): Promise<void> {
    if (!this.options || this.stopped) return;
    this.dirty = false;
    this.state.running = true;
    this.state.nextAttemptAt = null;
    this.state.lastAttemptAt = new Date().toISOString();
    try {
      await syncOnce(this.store, { ...this.options, signal: this.controller.signal });
      this.failures = 0;
      this.state.lastSuccessAt = new Date().toISOString();
      this.state.lastError = null;
    } catch (error) {
      if (this.stopped) return;
      this.failures += 1;
      const safe = publicError(error);
      this.state.lastError = { code: safe.code, message: safe.message };
    } finally {
      this.state.running = false;
      const seconds = this.failures ? Math.min(3600, Math.max(5, this.pollSeconds) * 2 ** Math.min(this.failures - 1, 8))
        : this.dirty ? 0 : this.pollSeconds;
      this.schedule(seconds);
    }
  }

  async stop(): Promise<void> {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this.state.nextAttemptAt = null;
    this.controller.abort();
    await this.pass;
  }
}

export async function startDaemon(options: {
  stateDir: string; socket: string; accountId: string; actorId: string;
  syncUrl?: string; tokenFile?: string; pollSeconds?: number; restore?: string;
}): Promise<{ server: Server; store: LocalStore; stop: () => Promise<void> }> {
  const socket = absolutePath(options.socket);
  if (Buffer.byteLength(socket) > 103) throw new MemoryError("unsafe_socket", 400, "Unix socket path is too long.");
  await safeParent(socket);
  try {
    await lstat(socket);
    throw new MemoryError("socket_occupied", 409, "Socket path is already occupied; refusing to replace it.");
  } catch (error) { if (!hasFsCode(error, "ENOENT")) throw error; }
  if ((options.syncUrl === undefined) !== (options.tokenFile === undefined)) {
    throw new MemoryError("invalid_sync_config", 400, "Synchronization URL and token file must be configured together.");
  }
  if (options.syncUrl !== undefined) syncBaseUrl(options.syncUrl);
  if (options.tokenFile !== undefined) absolutePath(options.tokenFile);
  const poll = options.pollSeconds ?? 60;
  if (!Number.isInteger(poll) || poll < 1 || poll > 3600) throw new MemoryError("invalid_request", 400, "Invalid synchronization interval.");
  const restore: unknown = options.restore === undefined ? undefined : JSON.parse(await readBoundedFile(options.restore, MAX_BACKUP_BYTES));
  const store = await LocalStore.open({ stateDir: options.stateDir, accountId: options.accountId, actorId: options.actorId, restore });
  const worker = new SyncWorker(store, options.syncUrl !== undefined && options.tokenFile !== undefined
    ? { url: options.syncUrl, tokenFile: options.tokenFile } : undefined, poll);
  let server: Server | undefined;
  try {
    const memory = new MemoryService(store);
    server = jsonServer(async (request, response) => {
      if (request.url === "/v1/status" && request.method === "GET") {
        sendJson(response, 200, { ...await store.status(), sync: worker.status() });
      } else if (request.url === "/v1/call" && request.method === "POST") {
        const call = callRequestSchema.parse(await readJson(request, MAX_PUSH_BYTES));
        const result = await memory.call(call.tool, call.arguments);
        if (!readOnlyTools.has(call.tool)) worker.trigger();
        sendJson(response, 200, result);
      } else if (request.url === "/v1/export" && request.method === "GET") {
        sendJson(response, 200, await store.exportBackup());
      } else if (request.url === "/v1/import" && request.method === "POST") {
        const result = await store.importBackup(await readJson(request, MAX_BACKUP_BYTES));
        worker.trigger();
        sendJson(response, 200, result);
      } else throw new MemoryError("not_found", 404, "Route not found.");
    });
    const listener = server;
    await new Promise<void>((resolve, reject) => {
      listener.once("error", reject);
      listener.listen(socket, () => { listener.off("error", reject); resolve(); });
    });
    await chmod(socket, 0o600);
    process.stderr.write("kebun-memory: warning: PGlite local durability is best-effort; acknowledged local writes may be lost after power failure; sync is not backup.\n");
    worker.trigger();
    let stopping: Promise<void> | undefined;
    const stop = (): Promise<void> => {
      stopping ??= (async () => {
        const workerStopped = worker.stop();
        await new Promise<void>((resolve, reject) => { listener.close((error) => error ? reject(error) : resolve()); });
        await workerStopped;
        await store.close();
      })();
      return stopping;
    };
    return { server: listener, store, stop };
  } catch (error) {
    const workerStopped = worker.stop();
    const listener = server;
    if (listener?.listening) await new Promise<void>((resolve) => { listener.close(() => resolve()); });
    await workerStopped;
    await store.close();
    throw error;
  }
}
