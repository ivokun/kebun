#!/usr/bin/env node
import { parseArgs } from "node:util";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { startDaemon } from "./daemon.js";
import { MemoryError, publicError } from "./errors.js";
import { absolutePath, readBoundedFile, writeExclusiveFile } from "./files.js";
import { localRequest } from "./http.js";
import { reexecWithFlock } from "./lock.js";
import { startMcp } from "./mcp.js";
import { daemonStatusSchema, importResultSchema, MAX_BACKUP_BYTES, memoryBackupSchema, uuidSchema } from "./protocol.js";
import { startSyncServer } from "./sync-server.js";

const usage = `kebun-memory 0.1.0
  daemon --state-dir ABS --socket ABS --account-id UUID --actor-id UUID [--sync-url HTTPS --token-file ABS] [--poll-seconds 60] [--restore ABS]
  mcp-stdio --socket ABS
  sync-server [--listen 127.0.0.1:8790] --database-url-file ABS --devices-file ABS [--rotate-epoch]
  export --socket ABS --output ABS
  import --socket ABS --input ABS
  status --socket ABS
`;

function required(values: Record<string, string | boolean | undefined>, name: string): string {
  const value = values[name];
  if (typeof value !== "string" || !value) throw new MemoryError("invalid_cli", 400, "Required CLI option is missing.");
  return value;
}

async function lifetime(close: () => Promise<void>): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    let stopping = false;
    const shutdown = () => {
      if (stopping) return;
      stopping = true;
      process.off("SIGINT", shutdown);
      process.off("SIGTERM", shutdown);
      void close().then(resolve, reject);
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
  });
}

export async function main(argv = process.argv.slice(2)): Promise<number> {
  // Includes the initial socket creation window, PGlite files and the lock file.
  process.umask(0o077);
  const command = argv[0];
  if (!command || command === "--help" || command === "help") { process.stdout.write(usage); return 0; }
  const common = { socket: { type: "string" } } satisfies NonNullable<Parameters<typeof parseArgs>[0]>["options"];
  switch (command) {
    case "daemon": {
      const { values } = parseArgs({ args: argv.slice(1), strict: true, options: {
        ...common, "state-dir": { type: "string" }, "account-id": { type: "string" }, "actor-id": { type: "string" },
        "sync-url": { type: "string" }, "token-file": { type: "string" }, "poll-seconds": { type: "string" }, restore: { type: "string" },
      } });
      const stateDir = absolutePath(required(values, "state-dir"));
      const socket = absolutePath(required(values, "socket"));
      const accountId = uuidSchema.parse(required(values, "account-id"));
      const actorId = uuidSchema.parse(required(values, "actor-id"));
      const wrapped = await reexecWithFlock(stateDir, argv);
      if (wrapped !== null) return wrapped;
      const daemon = await startDaemon({ stateDir, socket, accountId, actorId,
        ...(values["sync-url"] === undefined ? {} : { syncUrl: values["sync-url"] }),
        ...(values["token-file"] === undefined ? {} : { tokenFile: absolutePath(values["token-file"]) }),
        ...(values["poll-seconds"] === undefined ? {} : { pollSeconds: Number(values["poll-seconds"]) }),
        ...(values.restore === undefined ? {} : { restore: absolutePath(values.restore) }),
      });
      await lifetime(daemon.stop);
      return 0;
    }
    case "mcp-stdio": {
      const { values } = parseArgs({ args: argv.slice(1), strict: true, options: common });
      const server = await startMcp(absolutePath(required(values, "socket")));
      // stdin EOF is the ordinary lifecycle of a stdio MCP adapter.
      process.stdin.once("end", () => { void server.close().catch(() => undefined); });
      return 0;
    }
    case "sync-server": {
      const { values } = parseArgs({ args: argv.slice(1), strict: true, options: {
        listen: { type: "string", default: "127.0.0.1:8790" }, "database-url-file": { type: "string" },
        "devices-file": { type: "string" }, "rotate-epoch": { type: "boolean", default: false },
      } });
      const { server, store } = await startSyncServer({ listen: values.listen,
        databaseUrlFile: absolutePath(required(values, "database-url-file")),
        devicesFile: absolutePath(required(values, "devices-file")), rotateEpoch: values["rotate-epoch"],
      });
      await lifetime(async () => {
        await new Promise<void>((resolve, reject) => { server.close((error) => error ? reject(error) : resolve()); });
        await store.close();
      });
      return 0;
    }
    case "export": {
      const { values } = parseArgs({ args: argv.slice(1), strict: true, options: { ...common, output: { type: "string" } } });
      const backup = memoryBackupSchema.parse(await localRequest(absolutePath(required(values, "socket")), "GET", "/v1/export"));
      await writeExclusiveFile(absolutePath(required(values, "output")), `${JSON.stringify(backup)}\n`);
      return 0;
    }
    case "import": {
      const { values } = parseArgs({ args: argv.slice(1), strict: true, options: { ...common, input: { type: "string" } } });
      const backup = memoryBackupSchema.parse(JSON.parse(await readBoundedFile(absolutePath(required(values, "input")), MAX_BACKUP_BYTES)));
      const result = importResultSchema.parse(await localRequest(absolutePath(required(values, "socket")), "POST", "/v1/import", backup));
      process.stdout.write(`${JSON.stringify(result)}\n`);
      return 0;
    }
    case "status": {
      const { values } = parseArgs({ args: argv.slice(1), strict: true, options: common });
      const status = daemonStatusSchema.parse(await localRequest(absolutePath(required(values, "socket")), "GET", "/v1/status"));
      process.stdout.write(`${JSON.stringify(status)}\n`);
      return 0;
    }
    default: throw new MemoryError("invalid_cli", 400, "Unknown command. Run kebun-memory --help.");
  }
}

if (process.argv[1] && realpathSync(path.resolve(process.argv[1])) === fileURLToPath(import.meta.url)) {
  void main().then((code) => { process.exitCode = code; }).catch((error: unknown) => {
    const safe = publicError(error);
    process.stderr.write(`kebun-memory: ${safe.code}: ${safe.message}\n`);
    process.exitCode = 1;
  });
}
