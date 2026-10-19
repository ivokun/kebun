import { constants } from "node:fs";
import { chmod, lstat, mkdir, open, realpath } from "node:fs/promises";
import path from "node:path";
import { MemoryError } from "./errors.js";

export function absolutePath(value: string): string {
  if (!path.isAbsolute(value) || path.normalize(value) !== value || value.includes("\0")) {
    throw new MemoryError("unsafe_path", 400, "An absolute normalized path is required.");
  }
  return value;
}

export function hasFsCode(error: unknown, code: string): boolean {
  return error instanceof Error && "code" in error && error.code === code;
}

/** Directory ancestry is checked before use, never chmod through a symbolic link. */
export async function privateDirectory(value: string): Promise<string> {
  const directory = absolutePath(value);
  if (directory === path.parse(directory).root) throw new MemoryError("unsafe_path", 400, "The filesystem root cannot be a state directory.");
  const parts = directory.split(path.sep).filter(Boolean);
  let current = path.parse(directory).root;
  for (const part of parts) {
    current = path.join(current, part);
    try {
      await mkdir(current, { mode: 0o700 });
    } catch (error) {
      if (!hasFsCode(error, "EEXIST")) throw error;
    }
    const stat = await lstat(current);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new MemoryError("unsafe_path", 400, "Unsafe directory path.");
  }
  const stat = await lstat(directory);
  if (typeof process.getuid === "function" && stat.uid !== process.getuid()) {
    throw new MemoryError("unsafe_owner", 400, "State directory has a different owner.");
  }
  await chmod(directory, 0o700);
  return directory;
}

export async function safeParent(value: string): Promise<void> {
  const filename = absolutePath(value);
  const parent = path.dirname(filename);
  if (await realpath(parent) !== parent) throw new MemoryError("unsafe_path", 400, "Unsafe parent directory.");
  if (!(await lstat(parent)).isDirectory()) throw new MemoryError("unsafe_path", 400, "Invalid parent directory.");
}

export async function readBoundedFile(filename: string, limit: number, secret = false): Promise<string> {
  absolutePath(filename);
  // SOPS projects secrets through symlinks. Resolve read-only input, then prevent
  // a final-component swap and validate the opened descriptor, not the link.
  const resolved = await realpath(filename);
  const handle = await open(resolved, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > limit || (secret && (stat.mode & 0o077) !== 0)) {
      throw new MemoryError("unsafe_file", 400, "File type, size, or permissions are unsafe.");
    }
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of handle.createReadStream({ autoClose: false })) {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      size += bytes.length;
      if (size > limit) throw new MemoryError("payload_too_large", 413, "File exceeds the size limit.");
      chunks.push(bytes);
    }
    return Buffer.concat(chunks).toString("utf8");
  } finally {
    await handle.close();
  }
}

/** Never overwrite a backup, symlink, or any other existing directory entry. */
export async function writeExclusiveFile(filename: string, contents: string): Promise<void> {
  await safeParent(filename);
  const handle = await open(filename, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try {
    await handle.writeFile(contents, "utf8");
    await handle.sync();
  } finally {
    await handle.close();
  }
}
