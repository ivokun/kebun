import assert from 'node:assert/strict';
import test from 'node:test';
import {
  MemoryEventSchema, MemoryBackupSchema, ProvenanceSchema, CursorSchema,
  PushRequestSchema, PushResponseSchema, PullRequestSchema, PullResponseSchema,
  ServerInfoSchema,
} from '../dist/protocol.js';
import { ACCOUNT, ACTOR_A, PROVENANCE, entity, observation, retraction, uuid } from './fixtures/events.js';
import { pullPage } from './fixtures/local.js';

test('event schemas accept bounded UTF-8 text and canonical names but reject unknown fields and unsupported versions', () => {
  const parsed = MemoryEventSchema.parse(entity(1, ' Cafe\u0301 '));
  assert.equal(parsed.data.name, 'Café');
  assert.equal(MemoryEventSchema.safeParse(observation(2, '😀'.repeat(2048))).success, true);
  assert.equal(MemoryEventSchema.safeParse(observation(2, '😀'.repeat(2049))).success, false);
  for (const input of [
    { ...entity(3), version: 0 },
    { ...entity(3), version: 2 },
    { ...entity(3), extra: 'not allowed' },
    { ...entity(3), data: { ...entity(3).data, extra: 'not allowed' } },
    entity(3, 'NUL\0name'),
    entity(3, '   '),
    entity(3, 'x'.repeat(201)),
    observation(3, 'text', [uuid(1), uuid(1)]),
    observation(3, 'text', Array.from({ length: 101 }, (_, index) => uuid(index))),
    retraction(3, []),
    { ...retraction(3, [uuid(1)]), data: { targets: [uuid(1)], reason: 'purge' } },
  ]) {
    assert.equal(MemoryEventSchema.safeParse(input).success, false, JSON.stringify(input));
  }
});

test('scope is explicit and bounded; provenance requires a UTC verification time without accepting unknown keys', () => {
  for (const scope of ['project:kebun', 'topic:nixos.hosts', 'user:ivokun', `project:${'a'.repeat(120)}`]) {
    assert.equal(MemoryEventSchema.safeParse(entity(10, 'Kebun', 'project', { scope })).success, true, scope);
  }
  for (const scope of ['', 'project:', 'project:UPPER', 'global:kebun', 'project:two words', `project:${'a'.repeat(121)}`]) {
    assert.equal(MemoryEventSchema.safeParse(entity(10, 'Kebun', 'project', { scope })).success, false, scope);
  }
  for (const provenance of [
    {},
    { source: 'unverified' },
    { ...PROVENANCE, verifiedAt: '2026-10-19' },
    { ...PROVENANCE, verifiedAt: '2026-10-19T12:00:00+02:00' },
    { ...PROVENANCE, verifiedAt: '2026-02-31T00:00:00.000Z' },
    { ...PROVENANCE, source: 'é'.repeat(1025) },
    { ...PROVENANCE, revision: 'x'.repeat(129) },
    { ...PROVENANCE, confidence: 1 },
  ]) {
    assert.equal(ProvenanceSchema.safeParse(provenance).success, false, JSON.stringify(provenance));
  }
});

test('wire envelopes and decimal cursors are strict, bounded, and versioned', () => {
  const epoch = uuid(90);
  const cursor = { epoch, position: '9007199254740993' };
  assert.deepEqual(CursorSchema.parse(cursor), cursor, 'positions must not lose precision through Number');
  for (const position of ['-1', '01', '1.5', '1e3', '', ' 1', 1]) {
    assert.equal(CursorSchema.safeParse({ epoch, position }).success, false);
  }
  const envelopes = [
    [PushRequestSchema, { protocol: 1, epoch, events: [entity(20)] }],
    [PushResponseSchema, { protocol: 1, epoch, acceptedIds: [uuid(20)] }],
    [PullRequestSchema, { protocol: 1, cursor: null, limit: 100 }],
    [PullResponseSchema, pullPage([entity(20)], epoch)],
    [ServerInfoSchema, { protocol: 1, accountId: ACCOUNT, epoch, headPosition: '0' }],
  ];
  for (const [schema, value] of envelopes) {
    assert.equal(schema.safeParse(value).success, true);
    assert.equal(schema.safeParse({ ...value, protocol: 2 }).success, false);
    assert.equal(schema.safeParse({ ...value, extra: true }).success, false);
  }
  for (const limit of [0, 101, 1.5, '1']) {
    assert.equal(PullRequestSchema.safeParse({ protocol: 1, cursor: null, limit }).success, false);
  }
  assert.equal(PushRequestSchema.safeParse({
    protocol: 1, epoch, events: Array.from({ length: 101 }, (_, index) => entity(100 + index)),
  }).success, false);
});

test('backup format is complete and strict rather than a credential-bearing configuration dump', () => {
  const backup = {
    formatVersion: 1,
    accountId: ACCOUNT,
    actorId: ACTOR_A,
    events: [entity(30)],
    delivery: { pendingIds: [uuid(30)] },
    cursor: null,
    syncEpoch: null,
  };
  assert.deepEqual(MemoryBackupSchema.parse(backup), backup);
  for (const invalid of [
    { ...backup, formatVersion: 2 },
    { ...backup, token: 'test-only-not-a-real-credential' },
    { ...backup, delivery: { pendingIds: [uuid(30)], tokenFile: '/not/a/real/secret' } },
  ]) {
    assert.equal(MemoryBackupSchema.safeParse(invalid).success, false);
  }
});
