import assert from 'node:assert/strict';
import { stat } from 'node:fs/promises';
import test from 'node:test';
import { LocalStore } from '../dist/local-store.js';
import {
  ACCOUNT, ACTOR_A, ACTOR_B, OTHER_ACCOUNT, SCOPE,
  entity, observation, uuid,
} from './fixtures/events.js';
import { eventIds, localStore, pullPage } from './fixtures/local.js';

test('committed events, outbox acknowledgements, identity, and cursor survive a PGlite restart', { timeout: 60_000 }, async (t) => {
  const local = await localStore(t);
  const ownEvents = [entity(1), observation(2, 'Survives restart.')];
  const peerEvent = entity(3, 'NixOS', 'operating-system', { actorId: ACTOR_B });
  const epoch = uuid(900);

  await local.store.appendLocal(ownEvents);
  await local.store.acknowledge([ownEvents[0].eventId]);
  await local.store.applyPullPage(pullPage([peerEvent], epoch));
  await local.restart();

  assert.deepEqual(eventIds(await local.store.readEvents()), eventIds([...ownEvents, peerEvent]));
  assert.deepEqual(eventIds(await local.store.pending()), [ownEvents[1].eventId]);
  const status = await local.store.status();
  assert.equal(status.accountId, ACCOUNT);
  assert.equal(status.actorId, ACTOR_A);
  assert.equal(status.pendingCount, 1);
  assert.deepEqual(status.cursor, { epoch, position: '1' });
  assert.equal(status.syncEpoch, epoch);
  assert.equal((await stat(local.configuration.stateDir)).mode & 0o777, 0o700);
});

test('event IDs are immutable, canonical object key order is irrelevant, and a mixed collision rolls back entirely', async (t) => {
  const { store } = await localStore(t);
  const original = entity(10);
  await store.appendLocal([original]);
  const reordered = {
    data: { entityType: 'project', name: 'Kebun' },
    provenance: {
      revision: original.provenance.revision,
      verifiedAt: original.provenance.verifiedAt,
      source: original.provenance.source,
    },
    kind: original.kind,
    recordedAt: original.recordedAt,
    scope: original.scope,
    actorId: original.actorId,
    accountId: original.accountId,
    eventId: original.eventId,
    version: original.version,
  };

  await store.appendLocal([reordered]);
  await assert.rejects(store.appendLocal([
    observation(11, 'Must not be partially committed.'),
    { ...original, data: { name: 'Changed', entityType: 'project' } },
  ]));

  assert.deepEqual(await store.readEvents(), [original]);
  assert.deepEqual(eventIds(await store.pending()), [original.eventId]);
});

test('append validates the whole bounded batch before committing events or outbox records', async (t) => {
  const { store } = await localStore(t);
  const invalidEvents = [
    { ...entity(21), unexpected: true },
    { ...entity(21), version: 2 },
    { ...entity(21), eventId: 'not-a-uuid' },
    { ...entity(21), scope: 'project:Uppercase' },
    { ...entity(21), scope: 'arbitrary:memory' },
    { ...entity(21), scope: `project:${'a'.repeat(128)}` },
    { ...entity(21), recordedAt: '2026-10-19T12:00:00+02:00' },
    { ...entity(21), recordedAt: '2026-02-31T00:00:00.000Z' },
    { ...entity(21), provenance: { source: 'missing verification timestamp' } },
    { ...entity(21), provenance: { ...entity(21).provenance, extra: true } },
    { ...entity(21), provenance: { ...entity(21).provenance, source: 'x'.repeat(2049) } },
    { ...entity(21), provenance: { ...entity(21).provenance, revision: 'x'.repeat(129) } },
    entity(21, 'x'.repeat(201)),
    entity(21, ''),
    entity(21, 'Kebun', 'project', { accountId: OTHER_ACCOUNT }),
    entity(21, 'Kebun', 'project', { actorId: ACTOR_B }),
    observation(21, 'x'.repeat(8193)),
    observation(21, '😀'.repeat(2049)),
    { ...observation(21, 'text'), data: { entity: 'Kebun', text: 'text', supersedes: [], extra: true } },
  ];

  for (const invalid of invalidEvents) {
    await assert.rejects(store.appendLocal([entity(20), invalid]), JSON.stringify(invalid));
    assert.deepEqual(await store.readEvents(), []);
    assert.deepEqual(await store.pending(), []);
  }
  await assert.rejects(store.appendLocal(Array.from({ length: 101 }, (_, index) => entity(100 + index, `Entity ${index}`))));
  assert.deepEqual(await store.readEvents(), []);
});

test('names are trimmed and NFC-normalized at the shared validation boundary', async (t) => {
  const { store } = await localStore(t);
  await store.appendLocal([entity(30, '  Cafe\u0301  ')]);
  const [stored] = await store.readEvents();
  assert.equal(stored.data.name, 'Café');
});

test('a different persisted account or actor fails closed when reopening existing state', async (t) => {
  const local = await localStore(t);
  await local.store.appendLocal([entity(40)]);
  await local.close();

  for (const identity of [{ actorId: ACTOR_B }, { accountId: OTHER_ACCOUNT }]) {
    let unexpected;
    try {
      await assert.rejects(async () => { unexpected = await LocalStore.open({ ...local.configuration, ...identity }); });
    } finally {
      if (unexpected) await unexpected.close();
    }
  }
  await local.restart();
  assert.deepEqual(eventIds(await local.store.readEvents()), [uuid(40)]);
});

test('pulled events and cursor commit together without clearing local pending data or producing peer uploads', async (t) => {
  const { store } = await localStore(t);
  const localEvent = entity(50);
  const peerEvent = entity(51, 'Peer', 'project', { actorId: ACTOR_B });
  const epoch = uuid(901);
  await store.appendLocal([localEvent]);

  await store.applyPullPage(pullPage([peerEvent], epoch));
  await store.acknowledge([localEvent.eventId]);

  assert.deepEqual(eventIds(await store.readEvents()), eventIds([localEvent, peerEvent]));
  assert.deepEqual(await store.pending(), []);
  assert.deepEqual((await store.status()).cursor, { epoch, position: '1' });

  const before = await store.status();
  await assert.rejects(store.applyPullPage(pullPage([
    entity(52, 'Not committed', 'project', { actorId: ACTOR_B }),
    { ...peerEvent, data: { name: 'Mutated immutable ID', entityType: 'project' } },
  ], epoch, 2)));
  assert.deepEqual(await store.status(), before);
  assert.deepEqual(eventIds(await store.readEvents()), eventIds([localEvent, peerEvent]));
});

test('malformed, foreign-account, nonmonotonic, and invalid-version pull pages cannot move the cursor', async (t) => {
  const { store } = await localStore(t);
  const epoch = uuid(902);
  await store.applyPullPage(pullPage([entity(60, 'Peer', 'project', { actorId: ACTOR_B })], epoch));
  const valid = pullPage([entity(61, 'Next', 'project', { actorId: ACTOR_B })], epoch, 2);
  const pages = [
    { ...valid, protocol: 2 },
    { ...valid, extra: true },
    { ...valid, cursor: { epoch, position: '1' } },
    { ...valid, cursor: { epoch, position: '3' } },
    { ...valid, events: [{ position: '1', event: valid.events[0].event }] },
    { ...valid, events: [{ position: '-1', event: valid.events[0].event }] },
    { ...valid, events: [{ position: '02', event: valid.events[0].event }] },
    pullPage([entity(62, 'Foreign', 'project', { actorId: ACTOR_B, accountId: OTHER_ACCOUNT })], epoch, 2),
  ];
  const before = await store.status();
  for (const page of pages) {
    await assert.rejects(store.applyPullPage(page));
    assert.deepEqual(await store.status(), before);
    assert.deepEqual(eventIds(await store.readEvents()), [uuid(60)]);
  }
});

test('backup import is an atomic identity-checked union that preserves current cursor and requeues imported own events', async (t) => {
  const original = await localStore(t);
  await original.store.appendLocal([entity(70), observation(71, 'Original backup observation.')]);
  await original.store.acknowledge([uuid(70), uuid(71)]);
  const backup = await original.store.exportBackup();
  assert.equal(backup.formatVersion, 1);
  assert.equal(backup.accountId, ACCOUNT);
  assert.equal(backup.actorId, ACTOR_A);
  assert.deepEqual(eventIds(backup.events), [uuid(70), uuid(71)]);
  assert.doesNotMatch(JSON.stringify(backup), /tokenHash|bearer|password|databaseUrl/i);

  const target = await localStore(t);
  const epoch = uuid(903);
  await target.store.appendLocal([entity(72, 'Newer local state')]);
  await target.store.applyPullPage(pullPage([entity(73, 'Peer', 'project', { actorId: ACTOR_B })], epoch));
  await target.store.importBackup(backup);
  await target.store.importBackup(backup);

  assert.deepEqual(eventIds(await target.store.readEvents()), [70, 71, 72, 73].map(uuid));
  assert.deepEqual(eventIds(await target.store.pending()), [70, 71, 72].map(uuid));
  assert.deepEqual((await target.store.status()).cursor, { epoch, position: '1' });
  assert.equal((await target.store.status()).syncEpoch, epoch);

  const before = await target.store.exportBackup();
  const malformed = [
    { ...backup, formatVersion: 2 },
    { ...backup, accountId: OTHER_ACCOUNT },
    { ...backup, actorId: ACTOR_B },
    { ...backup, unknown: true },
    { ...backup, delivery: { pendingIds: [uuid(799)] } },
    { ...backup, delivery: { pendingIds: [uuid(70), uuid(70)] } },
    { ...backup, cursor: { epoch, position: '1' }, syncEpoch: uuid(904) },
    { ...backup, events: [entity(74), { ...entity(70), data: { name: 'Collision', entityType: 'project' } }] },
    { ...backup, events: [entity(74), { ...observation(71, 'Original backup observation.'), scope: 'invalid' }] },
  ];
  for (const invalid of malformed) {
    await assert.rejects(target.store.importBackup(invalid));
    assert.deepEqual(await target.store.exportBackup(), before);
  }
});

test('outbox limits are bounded and acknowledgements never change pull position', async (t) => {
  const { store } = await localStore(t);
  await store.appendLocal([entity(80), observation(81, 'Second event.')]);
  const [pending] = await store.pending(1);
  assert.ok([uuid(80), uuid(81)].includes(pending.eventId));
  await store.acknowledge([pending.eventId]);
  assert.equal((await store.pending(1)).length, 1);
  assert.equal((await store.status()).cursor, null);
  assert.equal((await store.status()).pendingCount, 1);
  assert.equal((await store.readEvents()).every((item) => item.scope === SCOPE), true);
});
