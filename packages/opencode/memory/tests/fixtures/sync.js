import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { ACTOR_A, ACTOR_B, principal } from './events.js';

// Public, inert fixture strings: never use these as deployment credentials.
export const TOKEN_A = 'memory-tests-only-device-a-not-a-real-secret';
export const TOKEN_B = 'memory-tests-only-device-b-not-a-real-secret';
export const SYNC_URL = 'https://memory.example.invalid';

export async function tokenFile(directory, token = TOKEN_A) {
  const filename = path.join(directory, 'test-only-token');
  await writeFile(filename, `${token}\n`, { mode: 0o600 });
  return filename;
}

export function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status, headers: { 'content-type': 'application/json' },
  });
}

export function serverTransport(server, options = {}) {
  const calls = [];
  const principals = new Map([
    [TOKEN_A, principal(ACTOR_A)],
    [TOKEN_B, principal(ACTOR_B)],
  ]);
  return {
    calls,
    fetch: async (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      if (url.origin !== SYNC_URL) throw new Error('Test transport refused an unexpected origin');
      const identity = principals.get(request.headers.get('authorization')?.replace(/^Bearer /, ''));
      const body = request.method === 'GET' ? undefined : await request.json();
      const call = { path: url.pathname, method: request.method, body, identity };
      calls.push(call);
      if (options.intercept) {
        const response = await options.intercept(call);
        if (response) return response;
      }
      if (!identity) return jsonResponse({ error: { code: 'unauthorized', message: 'Unauthorized.' } }, 401);
      try {
        if (url.pathname === '/v1/sync/info' && request.method === 'GET') {
          return jsonResponse(await server.info(identity));
        }
        if (url.pathname === '/v1/sync/push' && request.method === 'POST') {
          return jsonResponse(await server.push(identity, body));
        }
        if (url.pathname === '/v1/sync/pull' && request.method === 'POST') {
          return jsonResponse(await server.pull(identity, body));
        }
        return jsonResponse({ error: { code: 'not_found', message: 'Not found.' } }, 404);
      } catch (error) {
        return jsonResponse({ error: { code: error.code ?? 'invalid_request', message: 'Test server rejected request.' } }, error.status ?? 400);
      }
    },
  };
}
