import { createHash, timingSafeEqual } from "node:crypto";
import { type Server } from "node:http";
import { isIP } from "node:net";
import { z } from "zod";
import { MemoryError } from "./errors.js";
import { readBoundedFile } from "./files.js";
import { jsonServer, readJson, sendJson } from "./http.js";
import { MAX_PUSH_BYTES, principalSchema, requireProtocol, pullRequestSchema, pushRequestSchema, type Principal } from "./protocol.js";
import { PostgresServerStore } from "./server-store.js";

const deviceSchema = principalSchema.extend({ tokenHash: z.string().regex(/^[a-f0-9]{64}$/i).transform((value) => value.toLowerCase()) }).strict();
export const devicesSchema = z.array(deviceSchema).min(1).max(1000).superRefine((devices, context) => {
  const identities = new Set<string>();
  const hashes = new Set<string>();
  for (const device of devices) {
    const identity = `${device.accountId}:${device.actorId}`;
    if (identities.has(identity) || hashes.has(device.tokenHash)) context.addIssue({ code: "custom", message: "Duplicate device identity or hash." });
    identities.add(identity);
    hashes.add(device.tokenHash);
  }
});
export type Device = z.infer<typeof deviceSchema>;

export function authenticate(authorization: string | undefined, devices: readonly Device[]): Principal {
  const match = authorization?.match(/^Bearer ([\x21-\x7e]{1,8192})$/);
  const token = match?.[1];
  if (!token) throw new MemoryError("unauthorized", 401, "Authentication required.");
  const hash = createHash("sha256").update(token).digest();
  let principal: Principal | undefined;
  // Examine every registry entry, not a secret-dependent early-return position.
  for (const device of devices) {
    if (timingSafeEqual(hash, Buffer.from(device.tokenHash, "hex"))) {
      principal = { accountId: device.accountId, actorId: device.actorId };
    }
  }
  if (!principal) throw new MemoryError("unauthorized", 401, "Authentication required.");
  return principal;
}

export function loopbackListen(value: string): { host: string; port: number } {
  const match = value.match(/^(127(?:\.[0-9]{1,3}){3}|\[::1\]):([0-9]{1,5})$/);
  const host = match?.[1]?.replace(/^\[|\]$/g, "");
  const port = Number(match?.[2]);
  if (!host || !isIP(host) || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new MemoryError("unsafe_listener", 400, "The sync server must bind a numeric loopback address and valid port.");
  }
  return { host, port };
}

export function createSyncServer(store: PostgresServerStore, registry: readonly Device[]): Server {
  const devices = devicesSchema.parse(registry);
  return jsonServer(async (request, response) => {
    const principal = authenticate(request.headers.authorization, devices);
    if (request.url === "/v1/sync/info" && request.method === "GET") {
      sendJson(response, 200, await store.info(principal));
      return;
    }
    if (request.url === "/v1/sync/push" && request.method === "POST") {
      const value = await readJson(request, MAX_PUSH_BYTES);
      requireProtocol(value);
      sendJson(response, 200, await store.push(principal, pushRequestSchema.parse(value)));
      return;
    }
    if (request.url === "/v1/sync/pull" && request.method === "POST") {
      const value = await readJson(request, 16 * 1024);
      requireProtocol(value);
      sendJson(response, 200, await store.pull(principal, pullRequestSchema.parse(value)));
      return;
    }
    throw new MemoryError("not_found", 404, "Route not found.");
  });
}

export async function startSyncServer(options: {
  listen: string; databaseUrlFile: string; devicesFile: string; rotateEpoch: boolean;
}): Promise<{ server: Server; store: PostgresServerStore }> {
  const listen = loopbackListen(options.listen);
  const devices = devicesSchema.parse(JSON.parse(await readBoundedFile(options.devicesFile, 1024 * 1024)));
  const databaseUrl = (await readBoundedFile(options.databaseUrlFile, 16 * 1024, true)).trim();
  const store = await PostgresServerStore.open(databaseUrl);
  try {
    if (options.rotateEpoch) await store.rotateEpoch();
    const server = createSyncServer(store, devices);
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(listen.port, listen.host, () => { server.off("error", reject); resolve(); });
    });
    return { server, store };
  } catch (error) { await store.close(); throw error; }
}
