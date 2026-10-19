import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { PostgresServerStore } from '../dist/server-store.js';
import { ACCOUNT, ACTOR_A, ACTOR_B, entity, uuid } from './fixtures/events.js';
import { ephemeralPostgres } from './fixtures/postgres.js';
import { exited, remoteServer, spawnCli, unusedLoopbackPort } from './fixtures/process.js';
import { TOKEN_A, TOKEN_B } from './fixtures/sync.js';

const tokenHash = (token) => createHash('sha256').update(token).digest('hex');

test('HTTP sync-server authenticates every route, enforces the token principal, and classifies errors without echoing memory', { timeout: 90_000 }, async (t) => {
  const postgres = await ephemeralPostgres(t);
  const databaseFile = path.join(postgres.directory, 'database-url');
  const devicesFile = path.join(postgres.directory, 'devices.json');
  await writeFile(databaseFile, `${postgres.databaseUrl}\n`, { mode: 0o600 });
  const devices = [
    { accountId: ACCOUNT, actorId: ACTOR_A, tokenHash: tokenHash(TOKEN_A) },
    { accountId: ACCOUNT, actorId: ACTOR_B, tokenHash: tokenHash(TOKEN_B) },
  ];
  await writeFile(devicesFile, JSON.stringify(devices), { mode: 0o600 });
  const server = await remoteServer(t, ['--database-url-file', databaseFile, '--devices-file', devicesFile]);
  async function request(route, { token = TOKEN_A, body, raw } = {}) {
    const response = await fetch(`${server.url}${route}`, {
      method: body === undefined && raw === undefined ? 'GET' : 'POST',
      headers: {
        ...(token === null ? {} : { authorization: `Bearer ${token}` }),
        'content-type': 'application/json',
      },
      body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
      signal: AbortSignal.timeout(10_000),
    });
    const text = await response.text();
    return { status: response.status, body: JSON.parse(text), text };
  }

  for (const token of [null, '', 'revoked-test-only-token']) {
    for (const route of ['/v1/sync/info', '/v1/sync/push', '/v1/sync/pull']) {
      const result = await request(route, { token, ...(route.endsWith('/info') ? {} : { body: {} }) });
      assert.equal(result.status, 401, `${route} must authenticate before processing input`);
    }
  }
  const info = await request('/v1/sync/info');
  assert.equal(info.status, 200);
  assert.equal(info.body.protocol, 1);
  assert.equal(info.body.accountId, ACCOUNT);
  const epoch = info.body.epoch;
  const own = entity(3000);
  const pushed = await request('/v1/sync/push', { body: { protocol: 1, epoch, events: [own] } });
  assert.equal(pushed.status, 200);
  assert.deepEqual(pushed.body.acceptedIds, [own.eventId]);
  const observer = await PostgresServerStore.open(postgres.databaseUrl);
  try {
    const committed = await observer.pull({ accountId: ACCOUNT, actorId: ACTOR_B }, { protocol: 1, cursor: null, limit: 100 });
    assert.deepEqual(committed.events.map((item) => item.event.eventId), [own.eventId], 'an HTTP ack must be externally visible after COMMIT');
  } finally {
    await observer.close();
  }
  const retry = await request('/v1/sync/push', { body: { protocol: 1, epoch, events: [own] } });
  assert.equal(retry.status, 200);
  assert.equal((await request('/v1/sync/info')).body.headPosition, '1');
  const impersonation = await request('/v1/sync/push', { body: {
    protocol: 1, epoch, events: [entity(3001, 'Impersonation', 'project', { actorId: ACTOR_B })],
  } });
  assert.equal(impersonation.status, 401);

  const marker = 'PRIVATE_TEST_MEMORY_CONTENT_NOT_FOR_ERRORS';
  const collision = await request('/v1/sync/push', { body: {
    protocol: 1, epoch, events: [{ ...own, data: { name: marker, entityType: 'project' } }],
  } });
  assert.equal(collision.status, 409);
  assert.doesNotMatch(collision.text, new RegExp(marker));
  assert.equal((await request('/v1/sync/push', { body: { protocol: 2, epoch, events: [] } })).status, 426);
  assert.equal((await request('/v1/sync/push', { body: { protocol: 1, epoch: uuid(3999), events: [] } })).status, 409);
  assert.equal((await request('/v1/sync/push', { body: { protocol: 1, epoch, events: [], extra: marker } })).status, 400);
  assert.equal((await request('/v1/sync/push', { raw: '{not-json' })).status, 400);
  assert.equal((await request('/v1/sync/push', { raw: JSON.stringify({ padding: 'x'.repeat(1024 * 1024) }) })).status, 413);
  const pulled = await request('/v1/sync/pull', { token: TOKEN_B, body: { protocol: 1, cursor: null, limit: 1 } });
  assert.equal(pulled.status, 200);
  assert.equal(pulled.body.events[0].position, '1');
  assert.deepEqual(pulled.body.events[0].event, own);
  assert.doesNotMatch(server.stderr, new RegExp(marker));
  assert.doesNotMatch(server.stderr, new RegExp(TOKEN_A));

  for (const [name, registry] of [
    ['duplicate identity', [devices[0], { ...devices[1], actorId: ACTOR_A }]],
    ['duplicate hash', [devices[0], { ...devices[1], tokenHash: devices[0].tokenHash }]],
    ['malformed hash', [{ ...devices[0], tokenHash: 'plaintext-is-not-a-hash' }]],
    ['unknown field', [{ ...devices[0], token: TOKEN_A }]],
  ]) {
    const invalidFile = path.join(postgres.directory, `${name.replaceAll(' ', '-')}.json`);
    await writeFile(invalidFile, JSON.stringify(registry), { mode: 0o600 });
    const port = await unusedLoopbackPort();
    const invalid = spawnCli(t, [
      'sync-server', '--listen', `127.0.0.1:${port}`, '--database-url-file', databaseFile, '--devices-file', invalidFile,
    ]);
    assert.notEqual((await exited(invalid)).code, 0, name);
  }
  const publicPort = await unusedLoopbackPort();
  const publicBind = spawnCli(t, [
    'sync-server', '--listen', `0.0.0.0:${publicPort}`, '--database-url-file', databaseFile, '--devices-file', devicesFile,
  ]);
  assert.notEqual((await exited(publicBind)).code, 0, 'sync-server must refuse a public bind');
});
