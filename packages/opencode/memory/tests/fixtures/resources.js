import { spawn } from 'node:child_process';
import { mkdtemp, chmod, mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const packageRoot = fileURLToPath(new URL('../../', import.meta.url));
export const cliPath = path.join(packageRoot, 'dist', 'cli.js');

const cleanupStacks = new WeakMap();

export function cleanup(t, action) {
  if (!cleanupStacks.has(t)) {
    const actions = [];
    cleanupStacks.set(t, actions);
    t.after(async () => {
      const failures = [];
      for (const callback of actions.splice(0).reverse()) {
        try {
          await callback();
        } catch (error) {
          failures.push(error);
        }
      }
      cleanupStacks.delete(t);
      if (failures.length) throw new AggregateError(failures, 'Test resource cleanup failed');
    });
  }
  cleanupStacks.get(t).push(action);
}

export async function temporaryDirectory(t, label) {
  const root = process.env.MEMORY_TEST_TMPDIR ?? '/tmp/opencode';
  await mkdir(root, { recursive: true, mode: 0o700 });
  const directory = await mkdtemp(path.join(root, `memory-${label}-`));
  await chmod(directory, 0o700);
  cleanup(t, () => rm(directory, { recursive: true, force: true }));
  return directory;
}

export function cleanEnvironment(extra = {}) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('PG')));
  return { ...env, ...extra };
}

export function run(command, args, options = {}) {
  const { expectedExitCodes = [0], ...spawnOptions } = options;
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env: cleanEnvironment(),
      stdio: ['ignore', 'pipe', 'pipe'],
      ...spawnOptions,
    });
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, 30_000);
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once('close', (code, signal) => {
      clearTimeout(timer);
      if (timedOut) {
        reject(new Error(`Timed out: ${command} ${args.join(' ')}`));
      } else if (!expectedExitCodes.includes(code)) {
        reject(new Error(`${command} exited ${code ?? signal}: ${stderr}\n${stdout}`));
      } else {
        resolve({ stdout, stderr, code, signal });
      }
    });
  });
}

const stoppedChildren = new WeakSet();

function signalChild(child, signal, processGroup) {
  try {
    if (processGroup) process.kill(-child.pid, signal);
    else child.kill(signal);
  } catch (error) {
    if (error.code !== 'ESRCH') throw error;
  }
}

export async function stopChild(child, { processGroup = false, signal = 'SIGTERM' } = {}) {
  if (stoppedChildren.has(child)) return;
  if (child.exitCode !== null || child.signalCode !== null) {
    if (processGroup) signalChild(child, 'SIGKILL', true);
    stoppedChildren.add(child);
    return;
  }
  await new Promise((resolve) => {
    const timer = setTimeout(() => signalChild(child, 'SIGKILL', processGroup), 5_000);
    child.once('close', () => {
      clearTimeout(timer);
      if (processGroup) signalChild(child, 'SIGKILL', true);
      stoppedChildren.add(child);
      resolve();
    });
    // Let the CLI's wrapper forward a graceful termination exactly once.
    // A crash, or the bounded fallback, kills the entire owned process group.
    signalChild(child, signal, processGroup && signal !== 'SIGTERM');
  });
}
