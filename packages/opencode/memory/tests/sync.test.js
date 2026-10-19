import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import test from 'node:test';
import { reduceGraph } from '../dist/graph.js';
import { PostgresServerStore } from '../dist/server-store.js';
import { syncOnce } from '../dist/sync.js';
import {
  ACCOUNT, ACTOR_A, ACTOR_B, OTHER_ACCOUNT, SCOPE,
  entity, observation, principal, retraction, uuid,
} from './fixtures/events.js';
import { eventIds, localStore, pullPage } from './fixtures/local.js';
import { ephemeralPostgres } from './fixtures/postgres.js';
import { cleanup } from './fixtures/resources.js';
import { jsonResponse, serverTransport, SYNC_URL, TOKEN_A, TOKEN_B, tokenFile } from './fixtures/sync.js';

function synchronize(local, filename, transport) {
  return syncOnce(local.store, { url: SYNC_URL, tokenFile: filename, fetchImpl: transport.fetch });
}

test('syncOnce integration with real PostgreSQL 16 and two offline PGlite stores', { timeout: 120_000 }, async (t) => {
  const postgres = await ephemeralPostgres(t);
  const server = await PostgresServerStore.open(postgres.databaseUrl);
  cleanup(t, () => server.close());

  await t.test('offline devices reconnect in either order and converge while retaining concurrent corrections', async (t) => {
    const deviceA = await localStore(t);
    const deviceB = await localStore(t, { actorId: ACTOR_B });
    const fileA = await tokenFile(deviceA.directory, TOKEN_A);
    const fileB = await tokenFile(deviceB.directory, TOKEN_B);
    const transport = serverTransport(server);
    const original = observation(2001, 'Original shared fact.');
    const ownA = [entity(2000), original, observation(2002, 'Correction A.', [original.eventId])];
    const ownB = [
      entity(2003, 'Kebun', 'project', { actorId: ACTOR_B }),
      observation(2004, 'Correction B.', [original.eventId], { actorId: ACTOR_B }),
      retraction(2005, [uuid(2006)], 'deletion', { actorId: ACTOR_B }),
    ];
    await deviceA.store.appendLocal([...ownA, observation(2006, 'Delayed stale assertion.')]);
    await deviceB.store.appendLocal(ownB);
    assert.equal((await deviceA.store.status()).pendingCount, 4);
    assert.equal((await deviceB.store.status()).pendingCount, 3);

    // B uploads the correction and deletion before A's referenced additions.
    await synchronize(deviceB, fileB, transport);
    await synchronize(deviceA, fileA, transport);
    await synchronize(deviceB, fileB, transport);
    await synchronize(deviceA, fileA, transport);

    const graphA = reduceGraph(await deviceA.store.readEvents(), SCOPE);
    const graphB = reduceGraph(await deviceB.store.readEvents(), SCOPE);
    assert.deepEqual(graphA, graphB);
    assert.deepEqual(graphA.entities[0].observations, ['Correction A.', 'Correction B.']);
    assert.equal((await deviceA.store.status()).pendingCount, 0);
    assert.equal((await deviceB.store.status()).pendingCount, 0);
    assert.equal((await deviceA.store.readEvents()).length, 7);
    for (const call of transport.calls.filter((item) => item.path.endsWith('/push'))) {
      assert.equal(call.body.events.every((event) => event.actorId === call.identity.actorId), true, 'downloaded events must never loop back as another actor');
    }

    // Independent additions after another offline interval arrive in A-first order.
    await deviceA.store.appendLocal([entity(2007, 'A offline')]);
    await deviceB.store.appendLocal([entity(2008, 'B offline', 'project', { actorId: ACTOR_B })]);
    await synchronize(deviceA, fileA, transport);
    await synchronize(deviceB, fileB, transport);
    await synchronize(deviceA, fileA, transport);
    assert.deepEqual(await deviceA.store.readEvents(), await deviceB.store.readEvents());

    const bootstrap = await localStore(t);
    const bootstrapToken = await tokenFile(bootstrap.directory, TOKEN_A);
    await synchronize(bootstrap, bootstrapToken, transport);
    assert.deepEqual(await bootstrap.store.readEvents(), await deviceA.store.readEvents());
    assert.deepEqual(await bootstrap.store.pending(), []);
  });

  await t.test('a committed push with a lost acknowledgement is retried without losing pending data or duplicating server positions', async (t) => {
    const local = await localStore(t);
    const filename = await tokenFile(local.directory);
    const own = entity(2100, 'Acknowledgement-loss fixture');
    await local.store.appendLocal([own]);
    let dropped = false;
    const transport = serverTransport(server, {
      async intercept(call) {
        if (call.path.endsWith('/push') && !dropped) {
          dropped = true;
          await server.push(call.identity, call.body);
          throw new TypeError('fixture dropped the committed response');
        }
      },
    });
    await assert.rejects(synchronize(local, filename, transport));
    assert.deepEqual(eventIds(await local.store.pending()), [own.eventId]);
    assert.deepEqual(eventIds(await local.store.readEvents()), [own.eventId]);
    assert.equal((await local.store.status()).cursor, null);
    const head = (await server.info(principal())).headPosition;

    await local.restart();
    await synchronize(local, filename, transport);
    assert.equal((await server.info(principal())).headPosition, head);
    assert.deepEqual(await local.store.pending(), []);
    const retries = transport.calls.filter((call) => call.path.endsWith('/push'));
    assert.equal(retries.length, 2);
    assert.deepEqual(retries[0].body.events, retries[1].body.events);
  });

  await t.test('epoch change requeues all own acknowledged events, preserves pending/peer history, and clears the old cursor before replay', async (t) => {
    const local = await localStore(t);
    const filename = await tokenFile(local.directory);
    await local.store.appendLocal([entity(2200, 'Already acknowledged')]);
    const working = serverTransport(server);
    await synchronize(local, filename, working);
    assert.equal((await local.store.status()).pendingCount, 0);
    const before = await local.store.readEvents();
    const oldEpoch = (await local.store.status()).syncEpoch;
    assert.ok(before.some((event) => event.actorId === ACTOR_B), 'fixture must contain peer history before reset');
    await local.store.appendLocal([entity(2201, 'Still pending')]);
    await server.rotateEpoch();
    const offlinePush = serverTransport(server, {
      async intercept(call) {
        if (call.path.endsWith('/push')) throw new TypeError('fixture offline after epoch discovery');
      },
    });

    await assert.rejects(synchronize(local, filename, offlinePush));

    const reset = await local.store.status();
    assert.notEqual(reset.syncEpoch, oldEpoch);
    assert.equal(reset.cursor, null);
    const ownIds = (await local.store.readEvents()).filter((event) => event.actorId === ACTOR_A).map((event) => event.eventId).sort();
    assert.deepEqual(eventIds(await local.store.pending()), ownIds);
    assert.deepEqual(eventIds(await local.store.readEvents()), eventIds([...before, entity(2201, 'Still pending')]));

    await synchronize(local, filename, working);
    assert.deepEqual(await local.store.pending(), []);
    const lastPush = working.calls.filter((call) => call.path.endsWith('/push')).at(-1);
    assert.deepEqual(eventIds(lastPush.body.events), ownIds);
    assert.equal(lastPush.body.events.every((event) => event.actorId === ACTOR_A), true);
  });

  await t.test('missing, revoked, and changed token files fail safely and are read anew for every cycle', async (t) => {
    const local = await localStore(t);
    const filename = await tokenFile(local.directory, 'revoked-test-only-token');
    await local.store.appendLocal([entity(2300)]);
    const transport = serverTransport(server);
    await assert.rejects(synchronize(local, filename, transport));
    assert.deepEqual(eventIds(await local.store.pending()), [uuid(2300)]);
    assert.equal((await local.store.status()).cursor, null);

    await writeFile(filename, `${TOKEN_A}\n`, { mode: 0o600 });
    await synchronize(local, filename, transport);
    assert.deepEqual(await local.store.pending(), []);
    const cursor = (await local.store.status()).cursor;
    await local.store.appendLocal([entity(2301)]);
    await assert.rejects(syncOnce(local.store, { url: SYNC_URL, tokenFile: `${filename}-missing`, fetchImpl: transport.fetch }));
    assert.deepEqual(eventIds(await local.store.pending()), [uuid(2301)]);
    assert.deepEqual((await local.store.status()).cursor, cursor);
  });

  await t.test('an acknowledgement clears only its own in-flight batch and cannot erase a newer local write when the next request fails', async (t) => {
    const local = await localStore(t);
    const filename = await tokenFile(local.directory);
    const first = entity(2350, 'In-flight batch');
    const newer = entity(2351, 'Written during synchronization');
    await local.store.appendLocal([first]);
    let firstPush = true;
    const transport = serverTransport(server, {
      async intercept(call) {
        if (call.path.endsWith('/push') && firstPush) {
          firstPush = false;
          const response = await server.push(call.identity, call.body);
          await local.store.appendLocal([newer]);
          return jsonResponse(response);
        }
        if (call.path.endsWith('/push') || call.path.endsWith('/pull')) {
          throw new TypeError('fixture disconnected after the first acknowledgement');
        }
      },
    });

    await assert.rejects(synchronize(local, filename, transport));

    assert.deepEqual(eventIds(await local.store.readEvents()), [first.eventId, newer.eventId]);
    assert.deepEqual(eventIds(await local.store.pending()), [newer.eventId]);
    assert.equal((await local.store.status()).cursor, null);
  });

  await t.test('a large offline outbox is split by both event count and UTF-8 byte size and paginated pulls finish at the committed head', async (t) => {
    const local = await localStore(t);
    const filename = await tokenFile(local.directory);
    const events = Array.from({ length: 101 }, (_, index) => observation(2600 + index, `Fact ${index}: ${'x'.repeat(8170)}`, [], {
      provenance: { source: 'x'.repeat(2048), verifiedAt: '2026-10-19T10:00:00.000Z' },
    }));
    await local.store.appendLocal(events.slice(0, 80));
    await local.store.appendLocal(events.slice(80));
    const transport = serverTransport(server);

    await synchronize(local, filename, transport);

    const uploads = transport.calls.filter((call) => call.path.endsWith('/push'));
    assert.ok(uploads.length >= 2);
    assert.ok(uploads[0].body.events.length < 100, 'the byte limit must split even a count-valid batch');
    for (const { body } of uploads) {
      assert.ok(body.events.length <= 100);
      assert.ok(Buffer.byteLength(JSON.stringify(body), 'utf8') <= 1024 * 1024);
    }
    assert.deepEqual(eventIds(uploads.flatMap((call) => call.body.events)), eventIds(events));
    assert.deepEqual(await local.store.pending(), []);
    assert.ok(transport.calls.filter((call) => call.path.endsWith('/pull')).length >= 2);
    assert.equal((await local.store.status()).cursor.position, (await server.info(principal())).headPosition);
  });
});

test('simultaneous syncOnce callers share one bounded pass instead of racing outbox acknowledgements and cursors', { timeout: 30_000 }, async (t) => {
  const local = await localStore(t);
  const filename = await tokenFile(local.directory);
  const own = entity(2800);
  const epoch = uuid(2890);
  await local.store.appendLocal([own]);
  let releaseInfo;
  let markInfoEntered;
  const gate = new Promise((resolve) => { releaseInfo = resolve; });
  const infoEntered = new Promise((resolve) => { markInfoEntered = resolve; });
  cleanup(t, () => releaseInfo());
  const calls = [];
  const fetchImpl = async (input, init) => {
    const request = new Request(input, init);
    const route = new URL(request.url).pathname;
    calls.push(route);
    if (route.endsWith('/info')) {
      markInfoEntered();
      await gate;
      return jsonResponse({ protocol: 1, accountId: ACCOUNT, epoch, headPosition: '0' });
    }
    if (route.endsWith('/push')) {
      return jsonResponse({ protocol: 1, epoch, acceptedIds: [own.eventId] });
    }
    assert.equal(route, '/v1/sync/pull');
    return jsonResponse(pullPage([own], epoch));
  };
  const options = { url: SYNC_URL, tokenFile: filename, fetchImpl };
  const first = syncOnce(local.store, options);
  await Promise.race([infoEntered, first]);
  const second = syncOnce(local.store, options);
  releaseInfo();

  await Promise.all([first, second]);

  assert.deepEqual(calls, ['/v1/sync/info', '/v1/sync/push', '/v1/sync/pull']);
  assert.deepEqual(await local.store.pending(), []);
  assert.deepEqual((await local.store.status()).cursor, { epoch, position: '1' });
});

test('invalid remote envelopes cannot acknowledge arbitrary IDs or advance a local pull cursor', { timeout: 60_000 }, async (t) => {
  const local = await localStore(t);
  const filename = await tokenFile(local.directory);
  const epoch = uuid(2490);
  const own = entity(2400);
  const peer = entity(2401, 'Peer', 'project', { actorId: ACTOR_B });
  const baseline = pullPage([peer], epoch);
  await local.store.applyPullPage(baseline);
  const before = await local.store.exportBackup();
  const malformedPages = [
    { ...pullPage([entity(2402, 'Next', 'project', { actorId: ACTOR_B })], epoch, 2), protocol: 2 },
    pullPage([entity(2402, 'Foreign', 'project', { actorId: ACTOR_B, accountId: OTHER_ACCOUNT })], epoch, 2),
    { ...baseline, events: [], hasMore: true },
    { ...pullPage([entity(2402, 'Next', 'project', { actorId: ACTOR_B })], epoch, 2), cursor: { epoch, position: '99' } },
  ];
  for (const page of malformedPages) {
    let attemptedPull = false;
    const fetchImpl = async (input) => {
      const url = new URL(input instanceof Request ? input.url : input);
      if (url.pathname.endsWith('/info')) return jsonResponse({ protocol: 1, accountId: ACCOUNT, epoch, headPosition: '2' });
      assert.equal(url.pathname, '/v1/sync/pull');
      attemptedPull = true;
      return jsonResponse(page);
    };
    await assert.rejects(syncOnce(local.store, { url: SYNC_URL, tokenFile: filename, fetchImpl }));
    assert.equal(attemptedPull, true, 'the malformed page must actually reach the client validation boundary');
    assert.deepEqual(await local.store.exportBackup(), before);
  }
  await local.store.appendLocal([own]);
  const beforeForgedAck = await local.store.exportBackup();
  const forgedAck = async (input) => {
    const url = new URL(input instanceof Request ? input.url : input);
    if (url.pathname.endsWith('/info')) return jsonResponse({ protocol: 1, accountId: ACCOUNT, epoch, headPosition: '1' });
    if (url.pathname.endsWith('/push')) return jsonResponse({ protocol: 1, epoch, acceptedIds: [peer.eventId] });
    assert.fail('an invalid acknowledgement must abort before pulling');
  };
  await assert.rejects(syncOnce(local.store, { url: SYNC_URL, tokenFile: filename, fetchImpl: forgedAck }));
  assert.deepEqual(await local.store.exportBackup(), beforeForgedAck);
});

test('foreign-account info, unsupported protocol, HTTP transport, and non-JSON failures retain unsent events', async (t) => {
  const local = await localStore(t);
  const filename = await tokenFile(local.directory);
  await local.store.appendLocal([entity(2500)]);
  const epoch = uuid(2590);
  const before = await local.store.exportBackup();
  for (const value of [
    { protocol: 1, accountId: OTHER_ACCOUNT, epoch, headPosition: '0' },
    { protocol: 2, accountId: ACCOUNT, epoch, headPosition: '0' },
    { protocol: 1, accountId: ACCOUNT, epoch, headPosition: '0', extra: true },
  ]) {
    await assert.rejects(syncOnce(local.store, { url: SYNC_URL, tokenFile: filename, fetchImpl: async () => jsonResponse(value) }));
    assert.deepEqual(await local.store.exportBackup(), before);
  }
  await assert.rejects(syncOnce(local.store, {
    url: 'http://memory.example.invalid', tokenFile: filename,
    fetchImpl: async () => { assert.fail('insecure URL must be rejected before transport'); },
  }));
  await assert.rejects(syncOnce(local.store, {
    url: SYNC_URL, tokenFile: filename,
    fetchImpl: async () => new Response('<html>PRIVATE_TEST_RESPONSE_BODY</html>', { status: 503 }),
  }), (error) => !error.message.includes('PRIVATE_TEST_RESPONSE_BODY'));
  await assert.rejects(syncOnce(local.store, {
    url: SYNC_URL, tokenFile: filename,
    fetchImpl: async () => new Response('{}', { headers: { 'content-type': 'application/json', 'content-length': String(2 * 1024 * 1024 + 1) } }),
  }));
  assert.deepEqual(await local.store.exportBackup(), before);
});
