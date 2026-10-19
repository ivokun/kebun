import assert from 'node:assert/strict';
import test from 'node:test';
import { PostgresServerStore } from '../dist/server-store.js';
import { ACTOR_A, ACTOR_B, entity, observation, principal, uuid } from './fixtures/events.js';
import { eventIds } from './fixtures/local.js';
import { ephemeralPostgres } from './fixtures/postgres.js';
import { cleanup } from './fixtures/resources.js';

function account(number) {
  const accountId = uuid(number);
  return {
    owner: principal(ACTOR_A, accountId),
    peer: principal(ACTOR_B, accountId),
    entity: (id, name = 'Kebun', actorId = ACTOR_A) => entity(id, name, 'project', { accountId, actorId }),
  };
}

async function readAll(server, identity, limit = 2) {
  const events = [];
  const positions = [];
  let cursor = null;
  for (let pages = 0; pages < 200; pages += 1) {
    const page = await server.pull(identity, { protocol: 1, cursor, limit });
    for (const item of page.events) {
      assert.ok(BigInt(item.position) > BigInt(cursor?.position ?? '0'));
      if (positions.length) assert.ok(BigInt(item.position) > BigInt(positions.at(-1)));
      events.push(item.event);
      positions.push(item.position);
    }
    cursor = page.cursor;
    if (!page.hasMore) return { events, positions, cursor };
  }
  assert.fail('server pagination did not terminate within 200 pages');
}

test('PostgreSQL 16 server-store integration on a private ephemeral cluster', { timeout: 120_000 }, async (t) => {
  const postgres = await ephemeralPostgres(t);
  assert.equal(await postgres.sql('SHOW listen_addresses'), '', 'the test cluster must have no TCP listener');
  await postgres.sql("CREATE TABLE public.memory_test_guard (value text NOT NULL); INSERT INTO public.memory_test_guard VALUES ('unrelated schema remains untouched')");
  let server = await PostgresServerStore.open(postgres.databaseUrl);
  cleanup(t, () => server.close());

  await t.test('push/pull paginates committed positions; identical retries do not allocate another position', async () => {
    const tenant = account(1000);
    const info = await server.info(tenant.owner);
    assert.equal(info.protocol, 1);
    assert.equal(info.headPosition, '0');
    const events = [tenant.entity(1001), tenant.entity(1002, 'NixOS'), tenant.entity(1003, 'Den', ACTOR_B)];
    const first = await server.push(tenant.owner, { protocol: 1, epoch: info.epoch, events: events.slice(0, 2) });
    assert.deepEqual([...first.acceptedIds].sort(), eventIds(events.slice(0, 2)));
    await server.push(tenant.peer, { protocol: 1, epoch: info.epoch, events: events.slice(2) });
    const headBeforeRetry = (await server.info(tenant.owner)).headPosition;
    const retry = await server.push(tenant.owner, { protocol: 1, epoch: info.epoch, events: events.slice(0, 2) });
    assert.deepEqual([...retry.acceptedIds].sort(), eventIds(events.slice(0, 2)));
    assert.equal((await server.info(tenant.owner)).headPosition, headBeforeRetry);

    const result = await readAll(server, tenant.owner, 1);
    assert.deepEqual(eventIds(result.events), eventIds(events));
    assert.deepEqual(result.positions, ['1', '2', '3']);
    const empty = await server.pull(tenant.owner, { protocol: 1, cursor: result.cursor, limit: 1 });
    assert.deepEqual(empty.events, []);
    assert.equal(empty.hasMore, false);
    assert.deepEqual(empty.cursor, result.cursor);
  });

  await t.test('structurally identical JSON retries succeed; a mutated event ID rolls back the complete batch', async () => {
    const tenant = account(1100);
    const { epoch } = await server.info(tenant.owner);
    const original = tenant.entity(1101);
    await server.push(tenant.owner, { protocol: 1, epoch, events: [original] });
    const reordered = Object.fromEntries(Object.entries(original).reverse());
    reordered.data = { entityType: 'project', name: 'Kebun' };
    await server.push(tenant.owner, { protocol: 1, epoch, events: [reordered] });

    await assert.rejects(server.push(tenant.owner, {
      protocol: 1, epoch,
      events: [tenant.entity(1102, 'Must roll back'), { ...original, provenance: { ...original.provenance, source: 'Changed immutable content' } }],
    }), (error) => error.status === 409 && error.code === 'event_collision');
    assert.deepEqual(eventIds((await readAll(server, tenant.owner)).events), [original.eventId]);
    assert.equal((await server.info(tenant.owner)).headPosition, '1');
    await assert.rejects(server.push(tenant.peer, {
      protocol: 1, epoch, events: [{ ...original, actorId: ACTOR_B }],
    }), (error) => error.status === 409 && error.code === 'event_collision');
    assert.equal((await server.info(tenant.owner)).headPosition, '1');

    await assert.rejects(server.push(tenant.owner, {
      protocol: 1, epoch,
      events: [tenant.entity(1103), tenant.entity(1103, 'Collision within one batch')],
    }));
    assert.equal((await server.info(tenant.owner)).headPosition, '1');
  });

  await t.test('principal account and actor are authoritative; scopes never grant cross-account access', async () => {
    const tenant = account(1200);
    const foreign = account(1250);
    const { epoch } = await server.info(tenant.owner);
    for (const event of [tenant.entity(1201, 'Impersonates peer', ACTOR_B), foreign.entity(1251)]) {
      await assert.rejects(server.push(tenant.owner, { protocol: 1, epoch, events: [event] }));
    }
    await server.push(foreign.owner, { protocol: 1, epoch, events: [foreign.entity(1252)] });
    assert.deepEqual((await readAll(server, tenant.owner)).events, []);
    assert.equal((await server.info(tenant.owner)).headPosition, '0');
    assert.deepEqual(eventIds((await readAll(server, foreign.owner)).events), [uuid(1252)]);
  });

  await t.test('invalid protocol/epoch/bounds never change server history', async () => {
    const tenant = account(1300);
    const { epoch } = await server.info(tenant.owner);
    await assert.rejects(server.push(tenant.owner, { protocol: 2, epoch, events: [] }), (error) => error.status === 426);
    await assert.rejects(server.push(tenant.owner, { protocol: 1, epoch: uuid(1399), events: [] }), (error) => error.status === 409);
    await assert.rejects(server.pull(tenant.owner, { protocol: 1, cursor: { epoch: uuid(1399), position: '0' }, limit: 1 }), (error) => error.status === 409);
    await assert.rejects(server.push(tenant.owner, {
      protocol: 1, epoch, events: Array.from({ length: 101 }, (_, index) => tenant.entity(1310 + index, `Entity ${index}`)),
    }));
    for (const limit of [0, 101, -1, 1.5]) {
      await assert.rejects(server.pull(tenant.owner, { protocol: 1, cursor: null, limit }));
    }
    await assert.rejects(server.push(tenant.owner, {
      protocol: 1, epoch, events: [observation(1400, 'Private text must not appear in errors.', [], { accountId: tenant.owner.accountId, extra: true })],
    }));
    await assert.rejects(server.push(tenant.owner, {
      protocol: 1, epoch,
      events: Array.from({ length: 100 }, (_, index) => observation(1410 + index, 'x'.repeat(8192), [], {
        accountId: tenant.owner.accountId,
        provenance: { ...tenant.entity(1301).provenance, source: 'x'.repeat(2048) },
      })),
    }), (error) => error.status === 413);
    assert.equal((await server.info(tenant.owner)).headPosition, '0');
  });

  await t.test('concurrent appends and paginated pulls cannot skip a late commit or acknowledge uncommitted IDs', async () => {
    const tenant = account(1500);
    const { epoch } = await server.info(tenant.owner);
    const observer = await PostgresServerStore.open(postgres.databaseUrl);
    try {
      const expected = [];
      const seen = [];
      let cursor = null;
      // Each round races both actors, with deliberately reversed metadata times.
      // A successful push is checked through a separate Pool before continuing.
      for (let round = 0; round < 12; round += 1) {
        const base = 1510 + round * 10;
        const own = [tenant.entity(base, `A ${round}`), tenant.entity(base + 1, `A second ${round}`)];
        const peer = [tenant.entity(base + 2, `B ${round}`, ACTOR_B)];
        own[0].recordedAt = '2099-01-01T00:00:00.000Z';
        peer[0].recordedAt = '2000-01-01T00:00:00.000Z';
        expected.push(...own, ...peer);
        const appends = [
          server.push(tenant.owner, { protocol: 1, epoch, events: own }),
          server.push(tenant.peer, { protocol: 1, epoch, events: peer }),
        ];
        const during = await observer.pull(tenant.owner, { protocol: 1, cursor, limit: 1 });
        seen.push(...during.events);
        cursor = during.cursor;
        const acks = await Promise.all(appends);
        const committed = await readAll(observer, tenant.owner, 100);
        const committedIds = new Set(eventIds(committed.events));
        for (const ack of acks) for (const id of ack.acceptedIds) assert.ok(committedIds.has(id));
        for (let pages = 0; pages < 10; pages += 1) {
          const page = await observer.pull(tenant.owner, { protocol: 1, cursor, limit: 2 });
          seen.push(...page.events);
          cursor = page.cursor;
          if (!page.hasMore) break;
          assert.ok(pages < 9, 'bounded page drain must finish');
        }
      }
      assert.deepEqual(eventIds(seen.map((item) => item.event)), eventIds(expected));
      assert.deepEqual(seen.map((item) => item.position), Array.from({ length: expected.length }, (_, index) => String(index + 1)));
    } finally {
      await observer.close();
    }
  });

  await t.test('server restart preserves epoch and log; only explicit rotation invalidates old cursors', async () => {
    const tenant = account(1700);
    const before = await server.info(tenant.owner);
    await server.push(tenant.owner, { protocol: 1, epoch: before.epoch, events: [tenant.entity(1701)] });
    await server.close();
    server = await PostgresServerStore.open(postgres.databaseUrl);
    assert.equal((await server.info(tenant.owner)).epoch, before.epoch);
    assert.deepEqual(eventIds((await readAll(server, tenant.owner)).events), [uuid(1701)]);

    await server.rotateEpoch();
    const after = await server.info(tenant.owner);
    assert.notEqual(after.epoch, before.epoch);
    await assert.rejects(server.push(tenant.owner, { protocol: 1, epoch: before.epoch, events: [] }), (error) => error.status === 409);
    const replay = await server.push(tenant.owner, { protocol: 1, epoch: after.epoch, events: [tenant.entity(1701)] });
    assert.deepEqual(replay.acceptedIds, [uuid(1701)]);
    assert.equal((await server.info(tenant.owner)).headPosition, '1');
  });
  assert.equal(await postgres.sql('SELECT value FROM public.memory_test_guard'), 'unrelated schema remains untouched');
});
