import http, { type IncomingMessage, type ServerResponse } from "node:http";
import { z } from "zod";
import { MemoryError, publicError } from "./errors.js";
import { absolutePath } from "./files.js";
import { enforceJsonLimit, MAX_BACKUP_BYTES } from "./protocol.js";

export const callRequestSchema = z.strictObject({ tool: z.string().min(1).max(100), arguments: z.unknown() })
  .refine((value) => Object.hasOwn(value, "arguments"));
export const errorResponseSchema = z.strictObject({ error: z.strictObject({ code: z.string().min(1).max(100), message: z.string().max(200) }) });

export async function readJson(request: IncomingMessage, limit: number): Promise<unknown> {
  if (!/^application\/json(?:;|$)/i.test(request.headers["content-type"] ?? "")) {
    throw new MemoryError("invalid_request", 400, "Expected an application/json request.");
  }
  if (request.headers["content-encoding"] && request.headers["content-encoding"] !== "identity") {
    throw new MemoryError("invalid_request", 400, "Compressed request bodies are not accepted.");
  }
  const declared = request.headers["content-length"];
  if (declared && (!/^\d+$/.test(declared) || BigInt(declared) > BigInt(limit))) {
    request.resume();
    throw new MemoryError("payload_too_large", 413, "Request exceeds the size limit.");
  }
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += bytes.length;
    if (size > limit) {
      // Do not destroy before the classified 413 response is written.
      request.resume();
      throw new MemoryError("payload_too_large", 413, "Request exceeds the size limit.");
    }
    chunks.push(bytes);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new MemoryError("invalid_request", 400, "Request is not valid JSON."); }
}

export function sendJson(response: ServerResponse, status: number, value: unknown): void {
  enforceJsonLimit(value, MAX_BACKUP_BYTES);
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  response.end(body);
}

export function sendError(response: ServerResponse, error: unknown): void {
  const safe = publicError(error);
  if (response.headersSent || response.destroyed) { response.destroy(); return; }
  sendJson(response, safe.status, { error: { code: safe.code, message: safe.message } });
}

export function jsonServer(handler: (request: IncomingMessage, response: ServerResponse) => Promise<void>): http.Server {
  const server = http.createServer({ maxHeaderSize: 16 * 1024, requestTimeout: 30_000, headersTimeout: 10_000,
    keepAliveTimeout: 5_000, connectionsCheckingInterval: 5_000 }, (request, response) => {
    void handler(request, response).catch((error: unknown) => { sendError(response, error); });
  });
  server.maxRequestsPerSocket = 100;
  return server;
}

/** Small private-socket client: no proxy support, redirects, or filesystem access. */
export function localRequest(socket: string, method: "GET" | "POST", route: string, value?: unknown): Promise<unknown> {
  absolutePath(socket);
  const payload = value === undefined ? undefined : JSON.stringify(value);
  if (payload && Buffer.byteLength(payload) > MAX_BACKUP_BYTES) throw new MemoryError("payload_too_large", 413, "Local request exceeds the size limit.");
  return new Promise((resolve, reject) => {
    const request = http.request({ socketPath: socket, method, path: route,
      headers: { accept: "application/json", ...(payload === undefined ? {} : { "content-type": "application/json", "content-length": Buffer.byteLength(payload) }) } }, (response) => {
      const chunks: Buffer[] = [];
      let size = 0;
      if (!/^application\/json(?:;|$)/i.test(response.headers["content-type"] ?? "")) {
        response.resume();
        reject(new MemoryError("invalid_response", 502, "Invalid local response type."));
        return;
      }
      response.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > MAX_BACKUP_BYTES) {
          reject(new MemoryError("invalid_response", 502, "Local response exceeds the size limit."));
          response.destroy();
          return;
        }
        chunks.push(chunk);
      });
      response.on("error", () => reject(new MemoryError("daemon_unavailable", 503, "Memory daemon is unavailable.")));
      response.on("end", () => {
        try {
          const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          if ((response.statusCode ?? 500) >= 400) {
            const safe = errorResponseSchema.safeParse(parsed);
            reject(safe.success ? new MemoryError(safe.data.error.code, response.statusCode ?? 500, "Local memory request failed.")
              : new MemoryError("invalid_response", 502, "Invalid local error response."));
          } else resolve(parsed);
        } catch { reject(new MemoryError("invalid_response", 502, "Local response is not valid JSON.")); }
      });
    });
    request.setTimeout(30_000, () => { request.destroy(); });
    request.on("error", () => reject(new MemoryError("daemon_unavailable", 503, "Memory daemon is unavailable.")));
    request.end(payload);
  });
}
