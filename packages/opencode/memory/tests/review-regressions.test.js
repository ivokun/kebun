import assert from 'node:assert/strict';
import { request } from 'node:http';
import { rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { startDaemon } from '../dist/daemon.js';
import { MemoryService } from '../dist/memory-service.js';
import { MemoryBackupSchema, MemoryEventSchema } from '../dist/protocol.js';
import { PostgresServerStore } from '../dist/server-store.js';
import { syncOnce } from '../dist/sync.js';
import {
  ACCOUNT, ACTOR_A, ACTOR_B, INSTANT, PROVENANCE, SCOPE,
  entity, observation, principal, relation, rememberArguments, retraction, uuid,
} from './fixtures/events.js';
import { eventIds, localStore, pullPage } from './fixtures/local.js';
import { ephemeralPostgres } from './fixtures/postgres.js';
import { daemon, exited, spawnCli, unixRequest } from './fixtures/process.js';
import { cleanup, stopChild, temporaryDirectory } from './fixtures/resources.js';
import { jsonResponse, serverTransport, SYNC_URL, tokenFile } from './fixtures/sync.js';

const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

function backup(events, actorId = ACTOR_A) {
  return MemoryBackupSchema.parse({
    formatVersion: 1, accountId: ACCOUNT, actorId, events,
    delivery: { pendingIds: events.filter((event) => event.actorId === actorId).map((event) => event.eventId) },
    cursor: null, syncEpoch: null,
  });
}

function within(promise, milliseconds, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error(message)), milliseconds);
    }),
  ]).finally(() => clearTimeout(timer));
}

test('review: JSON escaping cannot make a count-valid pull exceed the client response limit', { timeout: 60_000 }, async (t) => {
  const postgres = await ephemeralPostgres(t);
  const server = await PostgresServerStore.open(postgres.databaseUrl);
  cleanup(t, () => server.close());
  const { epoch } = await server.info(principal(ACTOR_B));
  const events = Array.from({ length: 45 }, (_, index) => observation(40_000 + index, '\x01'.repeat(8192), [], { actorId: ACTOR_B }));
  for (let index = 0; index < events.length; index += 15) {
    const batch = { protocol: 1, epoch, events: events.slice(index, index + 15) };
    assert.ok(Buffer.byteLength(JSON.stringify(batch), 'utf8') <= 1024 * 1024, 'setup uses legal push batches');
    await server.push(principal(ACTOR_B), batch);
  }

  await t.test('serialized pages stay at or below 2 MiB and deliver every contiguous position before hasMore terminates', async () => {
    let cursor = null;
    let previous = 0n;
    const received = [];
    let terminated = false;
    for (let count = 0; count < 45; count += 1) {
      const page = await server.pull(principal(), { protocol: 1, cursor, limit: 100 });
      const bytes = Buffer.byteLength(JSON.stringify(page), 'utf8');
      assert.ok(bytes <= MAX_RESPONSE_BYTES, `pull serialized to ${bytes} bytes, above the ${MAX_RESPONSE_BYTES}-byte client limit`);
      assert.ok(page.events.length <= 100);
      for (const entry of page.events) {
        assert.equal(BigInt(entry.position), previous + 1n);
        previous += 1n;
        received.push(entry.event);
      }
      assert.equal(page.cursor.position, previous.toString());
      cursor = page.cursor;
      if (!page.hasMore) {
        terminated = true;
        break;
      }
      assert.ok(page.events.length > 0, 'a byte-limited page with hasMore must make progress');
    }
    assert.equal(terminated, true, 'bounded pagination must terminate');
    assert.deepEqual(eventIds(received), eventIds(events));
    assert.equal(previous, 45n);
  });

  await t.test('a bootstrap client can consume the escaped data instead of failing at the same cursor on every retry', async (t) => {
    const local = await localStore(t);
    const filename = await tokenFile(local.directory);
    const transport = serverTransport(server);
    const failures = [];
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        await syncOnce(local.store, { url: SYNC_URL, tokenFile: filename, fetchImpl: transport.fetch });
      } catch (error) {
        failures.push({ code: error.code, cursor: (await local.store.status()).cursor });
      }
    }
    assert.deepEqual(failures, [], 'legal escaped observations must not permanently strand a bootstrap client');
    assert.deepEqual(eventIds(await local.store.readEvents()), eventIds(events));
    assert.deepEqual((await local.store.status()).cursor, { epoch, position: '45' });
    assert.deepEqual(await local.store.pending(), []);
  });
});

test('review: a pull must be a gap-free extension of the committed local cursor', { timeout: 30_000 }, async (t) => {
  const epoch = uuid(41_900);
  const cases = [
    ['bootstrap position 3', false, [{ position: '3', event: entity(41_001, 'Skipped bootstrap', 'project', { actorId: ACTOR_B }) }]],
    ['inter-page gap from 1 to 3', true, [{ position: '3', event: entity(41_002, 'Skipped next event', 'project', { actorId: ACTOR_B }) }]],
    ['internal page gap from 2 to 4', true, [
      { position: '2', event: entity(41_003, 'Must roll back too', 'project', { actorId: ACTOR_B }) },
      { position: '4', event: entity(41_004, 'Skipped in page', 'project', { actorId: ACTOR_B }) },
    ]],
  ];
  for (const [name, hasPreviousPage, entries] of cases) {
    await t.test(name, async (t) => {
      const { store } = await localStore(t);
      await store.appendLocal([entity(41_000, 'Unsent local event')]);
      if (hasPreviousPage) await store.applyPullPage(pullPage([entity(41_010, 'Previously committed', 'project', { actorId: ACTOR_B })], epoch));
      const before = await store.exportBackup();
      const result = await Promise.allSettled([store.applyPullPage({
        protocol: 1, cursor: { epoch, position: entries.at(-1).position }, events: entries, hasMore: false,
      })]);
      assert.equal(result[0].status, 'rejected', `${name} must be rejected, not committed`);
      assert.deepEqual(await store.exportBackup(), before, 'rejected pages must preserve the event log, pending data, epoch and cursor atomically');
    });
  }
  await t.test('a contiguous extension remains valid', async (t) => {
    const { store } = await localStore(t);
    await store.applyPullPage(pullPage([entity(41_020, 'One', 'project', { actorId: ACTOR_B })], epoch));
    await store.applyPullPage(pullPage([
      entity(41_021, 'Two', 'project', { actorId: ACTOR_B }),
      entity(41_022, 'Three', 'project', { actorId: ACTOR_B }),
    ], epoch, 2));
    assert.equal((await store.status()).cursor.position, '3');
    assert.equal((await store.readEvents()).length, 3);
  });
});

test('review: failed restore validation cannot initialize the destination and poison a valid retry', { timeout: 90_000 }, async (t) => {
  const directory = await temporaryDirectory(t, 'review-restore');
  const valid = backup([entity(42_000), observation(42_001, 'Valid retry restores this fact.')]);
  const validFile = path.join(directory, 'valid.json');
  const malformedFile = path.join(directory, 'malformed.json');
  const foreignFile = path.join(directory, 'foreign.json');
  await writeFile(validFile, JSON.stringify(valid), { mode: 0o600 });
  await writeFile(malformedFile, '{not-valid-json', { mode: 0o600 });
  await writeFile(foreignFile, JSON.stringify(backup(valid.events.map((event) => ({ ...event, actorId: ACTOR_B })), ACTOR_B)), { mode: 0o600 });
  for (const [name, invalidFile] of [
    ['missing backup', path.join(directory, 'missing.json')],
    ['malformed backup', malformedFile],
    ['wrong-identity backup', foreignFile],
  ]) {
    await t.test(name, async (t) => {
      const destination = await temporaryDirectory(t, 'review-rst');
      const stateDir = path.join(destination, 'state');
      const socket = path.join(destination, 'memory.sock');
      const first = spawnCli(t, [
        'daemon', '--state-dir', stateDir, '--socket', socket,
        '--account-id', ACCOUNT, '--actor-id', ACTOR_A, '--restore', invalidFile,
      ]);
      assert.notEqual((await exited(first)).code, 0, 'invalid restore must fail');

      const retried = await daemon(t, { directory: destination, stateDir, socket, extraArgs: ['--restore', validFile] });

      const restored = await unixRequest(retried.socket, 'GET', '/v1/export');
      assert.deepEqual(eventIds(restored.body.events), eventIds(valid.events));
      assert.equal((await unixRequest(retried.socket, 'GET', '/v1/status')).body.pendingCount, 2);
    });
  }
  await t.test('an already initialized destination still refuses restore without changing its existing state', async (t) => {
    const owner = await daemon(t);
    const mutation = await unixRequest(owner.socket, 'POST', '/v1/call', { tool: 'remember', arguments: rememberArguments({ text: 'Existing state is not replaceable.' }) });
    assert.equal(mutation.status, 200);
    const before = (await unixRequest(owner.socket, 'GET', '/v1/export')).body;
    await stopChild(owner.child, { processGroup: true });
    await rm(owner.socket, { force: true });
    const invalidRestore = spawnCli(t, [...owner.args, '--restore', validFile]);
    assert.notEqual((await exited(invalidRestore)).code, 0);
    const reopened = await daemon(t, { directory: owner.directory, stateDir: owner.stateDir, socket: owner.socket });
    assert.deepEqual((await unixRequest(reopened.socket, 'GET', '/v1/export')).body, before);
  });
});

test('review: an unseen concurrent observation stays discoverable after the observed entity declaration is deleted', { timeout: 30_000 }, async (t) => {
  const { store } = await localStore(t);
  const service = new MemoryService(store);
  await service.call('remember', rememberArguments({ text: 'Observed and deleted.' }));
  await service.call('delete_entities', { scope: SCOPE, provenance: PROVENANCE, entityNames: ['Kebun'] });
  const unseen = observation(43_000, 'UNSEEN_CONCURRENT_REVIEW_FACT', [], { actorId: ACTOR_B });
  await store.applyPullPage(pullPage([unseen], uuid(43_900)));
  const before = await store.exportBackup();
  const complete = await service.call('read_graph', { scope: SCOPE });
  assert.deepEqual(complete.entities, [], 'no active declaration exists and none may be fabricated');
  assert.deepEqual(complete.assertions, [unseen]);

  await t.test('exact-text search finds the surviving observation even without an active entity declaration', async () => {
    const found = await service.call('search_nodes', { scope: SCOPE, query: unseen.data.text });
    assert.deepEqual(found.assertions, [unseen]);
    assert.deepEqual(found.entities, []);
  });
  await t.test('open_nodes by entity name exposes the assertion without synthesizing an entity', async () => {
    const found = await service.call('open_nodes', { scope: SCOPE, names: ['Kebun'] });
    assert.deepEqual(found.assertions, [unseen]);
    assert.deepEqual(found.entities, []);
  });
  assert.deepEqual(await store.exportBackup(), before, 'recall must never append a synthetic entity.add or any delivery metadata');
});

test('review: daemon shutdown aborts active sync before draining local requests and never starts a later network request', { timeout: 30_000 }, async (t) => {
  const directory = await temporaryDirectory(t, 'review-stop');
  const filename = await tokenFile(directory);
  const epoch = uuid(44_900);
  const originalFetch = globalThis.fetch;
  let owner;
  let heldRequest;
  let stopping;
  let stoppingRequested = false;
  let releaseInfo = () => {};
  let markInfoEntered;
  let infoSignal;
  const infoEntered = new Promise((resolve) => { markInfoEntered = resolve; });
  const requestsAfterStop = [];
  let abortedBeforeDrain = false;
  let stoppedWithoutReleasingInfo = false;
  globalThis.fetch = async (input, init) => {
    const outgoing = new Request(input, init);
    const route = new URL(outgoing.url).pathname;
    if (stoppingRequested) requestsAfterStop.push(route);
    if (route === '/v1/sync/info') {
      infoSignal = outgoing.signal;
      await new Promise((resolve, reject) => {
        const abort = () => reject(new DOMException('Test request was cancelled', 'AbortError'));
        releaseInfo = () => {
          outgoing.signal.removeEventListener('abort', abort);
          resolve();
        };
        if (outgoing.signal.aborted) abort();
        else outgoing.signal.addEventListener('abort', abort, { once: true });
        markInfoEntered();
      });
      return jsonResponse({ protocol: 1, accountId: ACCOUNT, epoch, headPosition: '0' });
    }
    if (route === '/v1/sync/push') {
      const body = await outgoing.json();
      return jsonResponse({ protocol: 1, epoch, acceptedIds: body.events.map((event) => event.eventId) });
    }
    assert.equal(route, '/v1/sync/pull');
    return jsonResponse({ protocol: 1, cursor: { epoch, position: '0' }, events: [], hasMore: false });
  };
  try {
    owner = await startDaemon({
      stateDir: path.join(directory, 'state'), socket: path.join(directory, 'memory.sock'),
      accountId: ACCOUNT, actorId: ACTOR_A, syncUrl: SYNC_URL, tokenFile: filename, pollSeconds: 3600,
    });
    await within(infoEntered, 3000, 'fixture: sync worker never issued its initial info request');
    let receivedRequest;
    const received = new Promise((resolve) => { receivedRequest = resolve; });
    owner.server.once('request', receivedRequest);
    const body = JSON.stringify({ tool: 'read_graph', arguments: { scope: SCOPE } });
    heldRequest = request({
      socketPath: path.join(directory, 'memory.sock'), method: 'POST', path: '/v1/call', agent: false,
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) },
    });
    heldRequest.on('error', () => {});
    heldRequest.write(body.slice(0, 1));
    await within(received, 3000, 'fixture: local request was not accepted before shutdown');
    const aborted = new Promise((resolve) => {
      if (infoSignal.aborted) resolve();
      else infoSignal.addEventListener('abort', resolve, { once: true });
    });
    stoppingRequested = true;
    stopping = owner.stop();
    try {
      await within(aborted, 1000, 'shutdown did not abort the in-flight sync while a local request was still draining');
      abortedBeforeDrain = true;
    } catch {
      // Record the defect, but always unblock both sides during finally below.
    }
    heldRequest.destroy();
    try {
      await within(stopping, 1000, 'shutdown remained dependent on the unanswered remote info request');
      stoppedWithoutReleasingInfo = true;
    } catch {
      // The old implementation must not leave the 30-second request timeout alive.
    }
  } finally {
    heldRequest?.destroy();
    releaseInfo();
    try {
      if (owner) await within(stopping ?? owner.stop(), 3000, 'fixture: daemon cleanup did not finish after releasing the gate');
    } finally {
      globalThis.fetch = originalFetch;
    }
  }
  assert.deepEqual({ abortedBeforeDrain, stoppedWithoutReleasingInfo, requestsAfterStop }, {
    abortedBeforeDrain: true, stoppedWithoutReleasingInfo: true, requestsAfterStop: [],
  }, 'stop must cancel before listener drain, finish without a remote response, and suppress every subsequent request');
});

function replaceField(value, fields, replacement) {
  const changed = structuredClone(value);
  let target = changed;
  for (const field of fields.slice(0, -1)) target = target[field];
  target[fields.at(-1)] = replacement;
  return changed;
}

const textFields = [
  ['entity name', entity(45_000), ['data', 'name']],
  ['entity type', entity(45_000), ['data', 'entityType']],
  ['observation entity', observation(45_000, 'Text'), ['data', 'entity']],
  ['observation text', observation(45_000, 'Text'), ['data', 'text']],
  ['relation from', relation(45_000), ['data', 'from']],
  ['relation to', relation(45_000), ['data', 'to']],
  ['relation type', relation(45_000), ['data', 'relationType']],
  ['provenance source', entity(45_000), ['provenance', 'source']],
  ['provenance revision', entity(45_000), ['provenance', 'revision']],
];
const invalidUnicode = [['NUL', '\0'], ['lone high surrogate', '\ud800'], ['lone low surrogate', '\udc00']];
const invalidTextEvents = textFields.flatMap(([name, original, fields]) => invalidUnicode.map(([description, invalid]) => ({
  label: `${name}: ${description}`,
  event: replaceField(original, fields, `TEST_ONLY_UNICODE_SENTINEL${invalid}tail`),
})));

function isValidationError(error) {
  return error?.name === 'ZodError' || (error?.status === 400 && error?.code === 'invalid_request');
}

test('review: every persisted string rejects NUL and lone surrogates at schema validation, not inside PostgreSQL jsonb', { timeout: 60_000 }, async (t) => {
  await t.test('all persisted textual fields reject invalid Unicode, including provenance.revision', () => {
    const accepted = invalidTextEvents.filter(({ event }) => MemoryEventSchema.safeParse(event).success).map(({ label }) => label);
    assert.deepEqual(accepted, [], 'these persisted strings incorrectly passed the public event schema');
  });

  await t.test('structural event strings and backup delivery/cursor identity strings reject invalid Unicode too', () => {
    const structuralEvents = [
      ['event ID', entity(45_100), ['eventId']],
      ['account ID', entity(45_100), ['accountId']],
      ['actor ID', entity(45_100), ['actorId']],
      ['scope', entity(45_100), ['scope']],
      ['recorded at', entity(45_100), ['recordedAt']],
      ['verified at', entity(45_100), ['provenance', 'verifiedAt']],
      ['event kind', entity(45_100), ['kind']],
      ['supersedes ID', observation(45_100, 'Text', [uuid(45_101)]), ['data', 'supersedes', 0]],
      ['retract target', retraction(45_100, [uuid(45_101)]), ['data', 'targets', 0]],
      ['retract reason', retraction(45_100, [uuid(45_101)]), ['data', 'reason']],
    ];
    const validBackup = { ...backup([entity(45_100)]), cursor: { epoch: uuid(45_900), position: '1' }, syncEpoch: uuid(45_900) };
    const backupFields = [['accountId'], ['actorId'], ['delivery', 'pendingIds', 0], ['cursor', 'epoch'], ['cursor', 'position'], ['syncEpoch']];
    for (const [description, invalid] of invalidUnicode) {
      for (const [name, original, fields] of structuralEvents) {
        assert.equal(MemoryEventSchema.safeParse(replaceField(original, fields, `invalid${invalid}`)).success, false, `${name}: ${description}`);
      }
      for (const fields of backupFields) {
        assert.equal(MemoryBackupSchema.safeParse(replaceField(validBackup, fields, `invalid${invalid}`)).success, false, `backup ${fields.join('.')}: ${description}`);
      }
    }
  });

  await t.test('well-formed astral Unicode remains valid in every textual field', () => {
    for (const [name, original, fields] of textFields) {
      const value = 'Valid astrals 😀 🌱 𠮷';
      const parsed = MemoryEventSchema.parse(replaceField(original, fields, value));
      let actual = parsed;
      for (const field of fields) actual = actual[field];
      assert.equal(actual, value, name);
    }
  });

  await t.test('invalid append batches fail schema validation before SQL and leave no events or outbox rows', async (t) => {
    const { store } = await localStore(t);
    const lateErrors = [];
    for (let index = 0; index < invalidTextEvents.length; index += 1) {
      const { label, event } = invalidTextEvents[index];
      const results = await Promise.allSettled([store.appendLocal([
        entity(46_000 + index * 2, 'Valid prefix must roll back'),
        { ...event, eventId: uuid(46_001 + index * 2) },
      ])]);
      const result = results[0];
      if (result.status !== 'rejected' || !isValidationError(result.reason)) {
        lateErrors.push({ field: label, status: result.status, errorCode: result.reason?.code ?? result.reason?.name });
      }
      assert.deepEqual(await store.readEvents(), [], `${label}: no partial batch may survive`);
      assert.deepEqual(await store.pending(), [], `${label}: no outgoing prefix may survive`);
    }
    assert.deepEqual(lateErrors, [], 'schema-invalid strings reached PGlite/SQL instead of being rejected at the public validation boundary');
  });

  const postgres = await ephemeralPostgres(t);
  const server = await PostgresServerStore.open(postgres.databaseUrl);
  cleanup(t, () => server.close());
  const { epoch } = await server.info(principal());
  await t.test('invalid push batches fail schema validation before SQL without committing an event or feed position', async () => {
    const lateErrors = [];
    for (let index = 0; index < invalidTextEvents.length; index += 1) {
      const { label, event } = invalidTextEvents[index];
      const results = await Promise.allSettled([server.push(principal(), { protocol: 1, epoch, events: [
        entity(47_000 + index * 2, 'Valid prefix must roll back'),
        { ...event, eventId: uuid(47_001 + index * 2) },
      ] })]);
      const result = results[0];
      if (result.status !== 'rejected' || !isValidationError(result.reason)) {
        lateErrors.push({ field: label, status: result.status, errorCode: result.reason?.code ?? result.reason?.name });
      }
      assert.equal((await server.info(principal())).headPosition, '0', `${label}: no prefix position may commit`);
      assert.deepEqual((await server.pull(principal(), { protocol: 1, cursor: null, limit: 100 })).events, []);
    }
    assert.deepEqual(lateErrors, [], 'schema-invalid strings reached PostgreSQL jsonb and exposed a database error instead of a validation error');
  });
  await t.test('valid astral text survives both local and PostgreSQL storage unchanged', async (t) => {
    const { store } = await localStore(t);
    const provenance = { source: 'Reviewed source 🌱', verifiedAt: INSTANT, revision: 'revision 😀' };
    const events = [
      entity(48_000, 'Kebun 😀', 'project 🌱', { provenance }),
      { ...observation(48_001, 'Valid supplementary character 𠮷', [], { provenance }), data: { entity: 'Kebun 😀', text: 'Valid supplementary character 𠮷', supersedes: [] } },
      relation(48_002, 'Kebun 😀', 'NixOS 🧪', { provenance }),
    ];
    await store.appendLocal(events);
    await server.push(principal(), { protocol: 1, epoch, events });
    assert.deepEqual(await store.readEvents(), events);
    assert.deepEqual((await server.pull(principal(), { protocol: 1, cursor: null, limit: 100 })).events.map((entry) => entry.event), events);
  });
});
