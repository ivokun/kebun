import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { request } from 'node:http';
import { createInterface } from 'node:readline';
import path from 'node:path';
import { ACCOUNT, ACTOR_A } from './events.js';
import {
  cleanEnvironment, cleanup, cliPath, packageRoot, stopChild, temporaryDirectory,
} from './resources.js';

export function spawnCli(t, args, { cwd = packageRoot } = {}) {
  const child = spawn(process.execPath, [cliPath, ...args], {
    cwd,
    env: cleanEnvironment(),
    stdio: ['pipe', 'pipe', 'pipe'],
    detached: true,
  });
  let stderr = '';
  child.stderr.on('data', (chunk) => { stderr = (stderr + chunk).slice(-65_536); });
  cleanup(t, () => stopChild(child, { processGroup: true }));
  return { child, get stderr() { return stderr; } };
}

export async function exited(process, timeout = 15_000) {
  if (process.child.exitCode !== null || process.child.signalCode !== null) {
    return { code: process.child.exitCode, signal: process.child.signalCode };
  }
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`CLI did not exit within ${timeout}ms: ${process.stderr}`));
    }, timeout);
    process.child.once('error', (error) => { clearTimeout(timer); reject(error); });
    process.child.once('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal }); });
  });
}

export function unixRequest(socketPath, method, route, value) {
  const body = value === undefined ? undefined : typeof value === 'string' ? value : JSON.stringify(value);
  return new Promise((resolve, reject) => {
    const outgoing = request({
      socketPath, method, path: route,
      headers: body === undefined ? {} : { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) },
      timeout: 10_000,
    }, (incoming) => {
      let raw = '';
      incoming.setEncoding('utf8');
      incoming.on('data', (chunk) => { raw += chunk; });
      incoming.on('error', reject);
      incoming.on('end', () => {
        try {
          resolve({ status: incoming.statusCode, headers: incoming.headers, body: JSON.parse(raw), raw });
        } catch (error) {
          reject(new Error(`Local route returned non-JSON: ${raw.slice(0, 500)}`, { cause: error }));
        }
      });
    });
    outgoing.on('error', reject);
    outgoing.on('timeout', () => outgoing.destroy(new Error('Local test request timed out')));
    outgoing.end(body);
  });
}

// The only timer-based retries are bounded process-readiness checks, never
// sleeps used to order assertions or wait for another agent's implementation.
async function ready(process, probe) {
  const deadline = Date.now() + 30_000;
  let retryDelay = 5;
  for (;;) {
    if (process.child.exitCode !== null || process.child.signalCode !== null) {
      throw new Error(`CLI exited before readiness: ${process.stderr}`);
    }
    try {
      const value = await probe();
      if (value) return value;
    } catch (error) {
      if (Date.now() >= deadline) throw new Error(`CLI not ready: ${process.stderr}`, { cause: error });
    }
    if (Date.now() >= deadline) throw new Error(`CLI readiness timed out: ${process.stderr}`);
    await new Promise((resolve) => setTimeout(resolve, retryDelay));
    retryDelay = Math.min(100, retryDelay * 2);
  }
}

export async function daemon(t, options = {}) {
  const directory = options.directory ?? await temporaryDirectory(t, 'daemon');
  const stateDir = options.stateDir ?? path.join(directory, 'state');
  const socket = options.socket ?? path.join(directory, 'memory.sock');
  const args = [
    'daemon', '--state-dir', stateDir, '--socket', socket,
    '--account-id', options.accountId ?? ACCOUNT,
    '--actor-id', options.actorId ?? ACTOR_A,
    ...(options.extraArgs ?? []),
  ];
  const process = spawnCli(t, args);
  await ready(process, async () => {
    const result = await unixRequest(socket, 'GET', '/v1/status');
    return result.status === 200 ? result : undefined;
  });
  return { child: process.child, get stderr() { return process.stderr; }, directory, stateDir, socket, args };
}

export async function unusedLoopbackPort() {
  const reservation = createServer();
  await new Promise((resolve, reject) => {
    reservation.once('error', reject);
    reservation.listen({ host: '127.0.0.1', port: 0 }, resolve);
  });
  const port = reservation.address().port;
  await new Promise((resolve, reject) => reservation.close((error) => error ? reject(error) : resolve()));
  return port;
}

export async function remoteServer(t, args) {
  const port = await unusedLoopbackPort();
  const process = spawnCli(t, ['sync-server', '--listen', `127.0.0.1:${port}`, ...args]);
  const url = `http://127.0.0.1:${port}`;
  await ready(process, async () => {
    const result = await fetch(`${url}/v1/sync/info`, { signal: AbortSignal.timeout(2_000) });
    return result.status === 401;
  });
  return { child: process.child, get stderr() { return process.stderr; }, url };
}

export function mcpClient(t, socket) {
  const process = spawnCli(t, ['mcp-stdio', '--socket', socket]);
  let nextId = 1;
  const pending = new Map();
  let protocolError;
  const lines = createInterface({ input: process.child.stdout });
  cleanup(t, () => {
    lines.close();
    for (const { timer, reject } of pending.values()) {
      clearTimeout(timer);
      reject(new Error('MCP fixture closed'));
    }
    pending.clear();
  });
  lines.on('line', (line) => {
    try {
      const message = JSON.parse(line);
      const awaiting = pending.get(message.id);
      if (!awaiting) return;
      clearTimeout(awaiting.timer);
      pending.delete(message.id);
      if (message.error) awaiting.reject(new Error(JSON.stringify(message.error)));
      else awaiting.resolve(message.result);
    } catch (error) {
      protocolError = error;
      for (const { reject, timer } of pending.values()) {
        clearTimeout(timer);
        reject(error);
      }
      pending.clear();
    }
  });
  process.child.once('error', (error) => {
    protocolError = error;
    for (const { reject, timer } of pending.values()) {
      clearTimeout(timer);
      reject(error);
    }
    pending.clear();
  });
  return {
    process,
    rpc(method, params) {
      if (protocolError) return Promise.reject(protocolError);
      return new Promise((resolve, reject) => {
        const id = nextId++;
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`MCP ${method} timed out: ${process.stderr}`));
        }, 15_000);
        pending.set(id, { resolve, reject, timer });
        process.child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
      });
    },
    notify(method, params = {}) {
      process.child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
    },
    async initialize() {
      const result = await this.rpc('initialize', {
        protocolVersion: '2024-11-05', capabilities: {},
        clientInfo: { name: 'kebun-memory-integration-test', version: '1.0.0' },
      });
      this.notify('notifications/initialized');
      return result;
    },
  };
}
