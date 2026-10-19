import { spawn } from "node:child_process";
import { constants } from "node:fs";
import { access, open, readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { MemoryError } from "./errors.js";
import { absolutePath, privateDirectory } from "./files.js";

const CHILD_MARKER = "KEBUN_MEMORY_INTERNAL_FLOCK_CHILD";

async function executable(): Promise<string> {
  const configured = process.env.KEBUN_MEMORY_FLOCK;
  if (configured) {
    const filename = absolutePath(configured);
    await access(filename, constants.X_OK);
    return filename;
  }
  for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
    if (!path.isAbsolute(directory)) continue;
    const filename = path.join(directory, "flock");
    try { await access(filename, constants.X_OK); return filename; } catch { /* try next PATH entry */ }
  }
  throw new MemoryError("flock_unavailable", 503, "A configured kernel flock executable is required.");
}

/** Verify the inherited descriptor really carries our kernel lock, not just an env marker. */
async function inheritedLock(lockPath: string): Promise<boolean> {
  const expected = await stat(lockPath);
  for (const descriptor of await readdir("/proc/self/fd")) {
    if (!/^\d+$/.test(descriptor)) continue;
    try {
      const actual = await stat(`/proc/self/fd/${descriptor}`);
      if (actual.dev !== expected.dev || actual.ino !== expected.ino) continue;
      const info = await readFile(`/proc/self/fdinfo/${descriptor}`, "utf8");
      if (new RegExp(`^lock:\\s+\\d+: FLOCK\\s+ADVISORY\\s+WRITE\\s+${process.pid}\\s`, "m").test(info)) return true;
    } catch { /* descriptors may disappear while inspecting /proc */ }
  }
  return false;
}

/**
 * Return null only in the proven lock-holding child. The outer CLI waits for its
 * reexec and forwards signals. flock --no-fork retains the lock descriptor across
 * exec, and exit 75 means an existing owner; we never unlink or steal the lock.
 */
export async function reexecWithFlock(stateDir: string, argv: readonly string[]): Promise<number | null> {
  const directory = await privateDirectory(stateDir);
  const lockPath = path.join(directory, "owner.lock");
  const handle = await open(lockPath, constants.O_RDWR | constants.O_CREAT | constants.O_NOFOLLOW, 0o600);
  try {
    const info = await handle.stat();
    if (!info.isFile() || (typeof process.getuid === "function" && info.uid !== process.getuid()) || info.nlink !== 1) {
      throw new MemoryError("unsafe_lock", 400, "Unsafe daemon lock file.");
    }
    await handle.chmod(0o600);
  } finally { await handle.close(); }
  if (process.env[CHILD_MARKER] === lockPath) {
    if (!await inheritedLock(lockPath)) throw new MemoryError("lock_not_held", 503, "Daemon kernel lock is not held.");
    delete process.env[CHILD_MARKER];
    return null;
  }
  const cli = process.argv[1];
  if (!cli) throw new MemoryError("invalid_invocation", 400, "Invalid CLI invocation.");
  const child = spawn(await executable(), ["--exclusive", "--nonblock", "--conflict-exit-code", "75", "--no-fork", lockPath,
    process.execPath, cli, ...argv], { stdio: "inherit", env: { ...process.env, [CHILD_MARKER]: lockPath } });
  const term = () => { child.kill("SIGTERM"); };
  const interrupt = () => { child.kill("SIGINT"); };
  process.on("SIGTERM", term);
  process.on("SIGINT", interrupt);
  try {
    return await new Promise<number>((resolve, reject) => {
      child.once("error", () => reject(new MemoryError("flock_failed", 503, "Cannot execute the daemon lock wrapper.")));
      child.once("exit", (code, signal) => resolve(code ?? (signal === "SIGINT" ? 130 : 143)));
    });
  } finally {
    process.off("SIGTERM", term);
    process.off("SIGINT", interrupt);
  }
}
