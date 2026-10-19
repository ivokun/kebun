import { MemoryError } from "./errors.js";
import { readBoundedFile } from "./files.js";
import { LocalStore } from "./local-store.js";
import {
  enforceJsonLimit, MAX_PUSH_BYTES, MAX_SYNC_RESPONSE_BYTES, pullResponseSchema, pushResponseSchema, serverInfoSchema,
  type MemoryEvent, type PullResponse,
} from "./protocol.js";

const activePasses = new WeakMap<LocalStore, Promise<void>>();
const remoteErrorSchemaCodes = new Set(["epoch_mismatch", "unsupported_protocol", "unauthorized", "event_collision", "invalid_request", "payload_too_large"]);

export function syncBaseUrl(value: string): URL {
  let url: URL;
  try { url = new URL(value); } catch { throw new MemoryError("invalid_sync_url", 400, "Invalid synchronization URL."); }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new MemoryError("invalid_sync_url", 400, "Synchronization requires an HTTPS URL without credentials, query, or fragment.");
  }
  url.pathname = url.pathname.replace(/\/$/, "");
  return url;
}

async function boundedResponse(response: Response, maxBytes: number): Promise<unknown> {
  if (!/^application\/json(?:;|$)/i.test(response.headers.get("content-type") ?? "")) {
    throw new MemoryError("invalid_response", 502, "Synchronization returned an invalid response.");
  }
  const declared = response.headers.get("content-length");
  if (declared && (!/^\d+$/.test(declared) || BigInt(declared) > BigInt(maxBytes))) {
    await response.body?.cancel();
    throw new MemoryError("invalid_response", 502, "Synchronization response exceeds the size limit.");
  }
  if (!response.body) throw new MemoryError("invalid_response", 502, "Synchronization response has no body.");
  const reader = response.body.getReader();
  const buffers: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.length;
      if (size > maxBytes) throw new MemoryError("invalid_response", 502, "Synchronization response exceeds the size limit.");
      buffers.push(next.value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    throw error;
  } finally { reader.releaseLock(); }
  try { return JSON.parse(Buffer.concat(buffers).toString("utf8")); }
  catch { throw new MemoryError("invalid_response", 502, "Synchronization response is not valid JSON."); }
}

async function cycle(store: LocalStore, options: { url: string; tokenFile: string; fetchImpl?: typeof fetch; signal?: AbortSignal }): Promise<void> {
  options.signal?.throwIfAborted();
  const base = syncBaseUrl(options.url);
  let token: string;
  try { token = (await readBoundedFile(options.tokenFile, 8192, true)).trim(); }
  catch { throw new MemoryError("token_unavailable", 503, "Synchronization token is unavailable."); }
  if (!token || !/^[\x21-\x7e]+$/.test(token)) throw new MemoryError("token_unavailable", 503, "Synchronization token is unavailable.");
  const request = async (route: string, body?: unknown): Promise<unknown> => {
    options.signal?.throwIfAborted();
    const url = new URL(`${base.toString().replace(/\/$/, "")}${route}`);
    const timeout = AbortSignal.timeout(30_000);
    const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
    let response: Response;
    try {
      response = await (options.fetchImpl ?? fetch)(url, {
        method: body === undefined ? "GET" : "POST",
        headers: { authorization: `Bearer ${token}`, accept: "application/json", ...(body === undefined ? {} : { "content-type": "application/json" }) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        redirect: "error", signal,
      });
    } catch { throw new MemoryError("network_unavailable", 503, "Synchronization service is unavailable."); }
    options.signal?.throwIfAborted();
    const value = await boundedResponse(response, MAX_SYNC_RESPONSE_BYTES);
    options.signal?.throwIfAborted();
    if (!response.ok) {
      let code = "sync_rejected";
      if (typeof value === "object" && value !== null && "error" in value && typeof value.error === "object"
        && value.error !== null && "code" in value.error && typeof value.error.code === "string"
        && remoteErrorSchemaCodes.has(value.error.code)) code = value.error.code;
      throw new MemoryError(code, response.status, "Synchronization request was rejected.");
    }
    return value;
  };

  const infoResult = serverInfoSchema.safeParse(await request("/v1/sync/info"));
  if (!infoResult.success || infoResult.data.accountId !== store.accountId) {
    throw new MemoryError("invalid_response", 502, "Synchronization identity or info envelope is invalid.");
  }
  const info = infoResult.data;
  options.signal?.throwIfAborted();
  await store.reconcileEpoch(info.epoch);

  // Drain a snapshot of the outbox. Writes during this pass are handled by the
  // daemon's pending trigger, without starving downloads under continuous writes.
  let remaining = (await store.status()).pendingCount;
  while (remaining > 0) {
    options.signal?.throwIfAborted();
    const pending = await store.pending(Math.min(100, remaining));
    if (pending.length === 0) break;
    const batch: MemoryEvent[] = [];
    for (const event of pending) {
      const candidate = { protocol: 1, epoch: info.epoch, events: [...batch, event] };
      try { enforceJsonLimit(candidate, MAX_PUSH_BYTES); }
      catch {
        if (batch.length === 0) throw new MemoryError("payload_too_large", 413, "An event exceeds the synchronization limit.");
        break;
      }
      batch.push(event);
    }
    const parsed = pushResponseSchema.safeParse(await request("/v1/sync/push", { protocol: 1, epoch: info.epoch, events: batch }));
    if (!parsed.success || parsed.data.epoch !== info.epoch) throw new MemoryError("invalid_response", 502, "Invalid push acknowledgement.");
    const allowed = new Set(batch.map((event) => event.eventId));
    if (parsed.data.acceptedIds.some((id) => !allowed.has(id)) || parsed.data.acceptedIds.length !== allowed.size) {
      throw new MemoryError("invalid_response", 502, "Push acknowledgement does not match the submitted events.");
    }
    options.signal?.throwIfAborted();
    await store.acknowledge(parsed.data.acceptedIds);
    remaining -= batch.length;
  }

  // A pass has a bounded page budget. A remaining backlog retries through the
  // worker's bounded backoff; no cursor skips or unbounded process growth.
  for (let pageCount = 0; pageCount < 1000; pageCount += 1) {
    options.signal?.throwIfAborted();
    const status = await store.status();
    const parsed = pullResponseSchema.safeParse(await request("/v1/sync/pull", { protocol: 1, cursor: status.cursor, limit: 100 }));
    if (!parsed.success) throw new MemoryError("invalid_response", 502, "Invalid pull response.");
    const page: PullResponse = parsed.data;
    if (page.cursor.epoch !== info.epoch || page.events.length > 100) throw new MemoryError("invalid_response", 502, "Invalid pull epoch or page size.");
    options.signal?.throwIfAborted();
    await store.applyPullPage(page);
    if (!page.hasMore) return;
  }
  throw new MemoryError("sync_backlog", 503, "Synchronization has more pages to reconcile.");
}

/** Concurrent callers share one pass; even token or protocol failure leaves local writes available. */
export function syncOnce(store: LocalStore, options: { url: string; tokenFile: string; fetchImpl?: typeof fetch; signal?: AbortSignal }): Promise<void> {
  const existing = activePasses.get(store);
  if (existing) return existing;
  const pass = cycle(store, options).finally(() => { activePasses.delete(store); });
  activePasses.set(store, pass);
  return pass;
}
