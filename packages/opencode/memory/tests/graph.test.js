import assert from 'node:assert/strict';
import test from 'node:test';
import { reduceGraph } from '../dist/graph.js';
import {
  ACTOR_B, OTHER_ACCOUNT, OTHER_SCOPE, PROVENANCE, SCOPE,
  entity, observation, permutations, relation, retraction, uuid,
} from './fixtures/events.js';

test('every arrival order converges, including corrections and tombstones received before their targets', () => {
  const events = [
    entity(1),
    observation(2, 'Superseded claim.'),
    observation(3, 'Reviewed correction.', [uuid(2)], { actorId: ACTOR_B }),
    observation(4, 'Deleted claim.'),
    retraction(5, [uuid(4)], 'deletion'),
  ];
  const expected = {
    entities: [{ name: 'Kebun', entityType: 'project', observations: ['Reviewed correction.'], assertionIds: [uuid(1), uuid(3)] }],
    relations: [],
    assertions: [events[0], events[2]],
    conflicts: [],
  };

  for (const arrival of permutations(events)) {
    assert.deepEqual(reduceGraph(arrival, SCOPE), expected);
  }
  assert.deepEqual(reduceGraph([...events, events[0], events[2]], SCOPE), expected, 'identical event replay must not duplicate assertions');
});

test('concurrent corrections remain active with both assertion IDs and their original provenance', () => {
  const original = observation(11, 'Original claim.');
  const left = observation(12, 'Correction A.', [original.eventId], {
    recordedAt: '2099-01-01T00:00:00.000Z',
    provenance: { ...PROVENANCE, source: 'review A' },
  });
  const right = observation(13, 'Correction B.', [original.eventId], {
    actorId: ACTOR_B,
    recordedAt: '2000-01-01T00:00:00.000Z',
    provenance: { ...PROVENANCE, source: 'review B' },
  });

  for (const arrival of permutations([entity(10), original, left, right])) {
    const graph = reduceGraph(arrival, SCOPE);
    assert.deepEqual(graph.entities[0].observations, ['Correction A.', 'Correction B.']);
    assert.deepEqual(graph.assertions.filter((item) => item.kind === 'observation.add'), [left, right]);
  }
});

test('conflicting entity types produce null and an explicit conflict instead of a timestamp winner', () => {
  const project = entity(20, 'Kebun', 'project', { recordedAt: '2099-01-01T00:00:00.000Z' });
  const workstation = entity(21, 'Kebun', 'workstation', { actorId: ACTOR_B, recordedAt: '2000-01-01T00:00:00.000Z' });

  for (const arrival of permutations([project, workstation])) {
    const graph = reduceGraph(arrival, SCOPE);
    assert.equal(graph.entities[0].entityType, null);
    assert.deepEqual(graph.conflicts, [{ entity: 'Kebun', entityTypes: ['project', 'workstation'], assertionIds: [uuid(20), uuid(21)] }]);
  }
  const curated = reduceGraph([project, workstation, retraction(22, [workstation.eventId])], SCOPE);
  assert.equal(curated.entities[0].entityType, 'project');
  assert.deepEqual(curated.conflicts, []);
});

test('retractions cannot be retracted and suppression remains transitive through a superseded correction', () => {
  const events = [
    entity(30),
    observation(31, 'Original.'),
    observation(32, 'First correction.', [uuid(31)]),
    observation(33, 'Final correction.', [uuid(32)]),
    retraction(34, [uuid(33)], 'deletion'),
    retraction(35, [uuid(34)], 'deletion'),
  ];
  for (const arrival of [events, [...events].reverse(), [events[5], events[3], events[1], events[4], events[2], events[0]]]) {
    const graph = reduceGraph(arrival, SCOPE);
    assert.deepEqual(graph.entities[0].observations, []);
    assert.deepEqual(graph.assertions, [events[0]]);
  }
});

test('scope and account boundaries prevent a foreign retraction or supersession from suppressing an assertion', () => {
  const kept = observation(41, 'Still active.');
  const foreignScope = retraction(42, [kept.eventId], 'deletion', { scope: OTHER_SCOPE });
  const foreignAccount = retraction(43, [kept.eventId], 'deletion', { accountId: OTHER_ACCOUNT });
  const foreignCorrection = observation(44, 'Foreign-scope correction.', [kept.eventId], { scope: OTHER_SCOPE });

  const graph = reduceGraph([entity(40), kept, foreignScope, foreignAccount, foreignCorrection], SCOPE);
  assert.deepEqual(graph.entities[0].observations, ['Still active.']);
  assert.deepEqual(graph.assertions.map((item) => item.eventId), [uuid(40), uuid(41)]);
  assert.deepEqual(reduceGraph([entity(40), kept], OTHER_SCOPE).entities, []);
});

test('equal relations retain separate assertion provenance and observed removal retracts only the selected ID', () => {
  const first = relation(52);
  const concurrent = relation(53, 'Kebun', 'NixOS', { actorId: ACTOR_B });
  const events = [entity(50), entity(51, 'NixOS', 'operating-system'), first, concurrent];
  const graph = reduceGraph(events, SCOPE);
  assert.deepEqual(graph.relations, [{ from: 'Kebun', to: 'NixOS', relationType: 'uses', assertionIds: [uuid(52), uuid(53)] }]);
  assert.deepEqual(graph.assertions.filter((item) => item.kind === 'relation.add'), [first, concurrent]);

  const removed = reduceGraph([retraction(54, [first.eventId], 'deletion'), ...events], SCOPE);
  assert.deepEqual(removed.relations[0].assertionIds, [concurrent.eventId]);
});

test('graph entrypoint validates its scope and events and refuses conflicting immutable event IDs', () => {
  const original = entity(60);
  assert.throws(() => reduceGraph([original], 'unscoped'));
  assert.throws(() => reduceGraph([{ ...original, version: 2 }], SCOPE));
  assert.throws(() => reduceGraph([{ ...original, extra: true }], SCOPE));
  assert.throws(() => reduceGraph([original, { ...original, data: { name: 'Changed', entityType: 'project' } }], SCOPE));
  assert.deepEqual(reduceGraph([], SCOPE), { entities: [], relations: [], assertions: [], conflicts: [] });
});
