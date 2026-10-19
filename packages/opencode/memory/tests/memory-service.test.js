import assert from 'node:assert/strict';
import test from 'node:test';
import { MemoryService } from '../dist/memory-service.js';
import {
  ACTOR_B, OTHER_SCOPE, PROVENANCE, SCOPE, entity, observation, rememberArguments, uuid,
} from './fixtures/events.js';
import { localStore, pullPage } from './fixtures/local.js';

async function serviceFixture(t) {
  const local = await localStore(t);
  return { ...local, service: new MemoryService(local.store) };
}

test('remember atomically ensures an entity and observation with verified provenance and supports explicit corrections', async (t) => {
  const { store, service } = await serviceFixture(t);
  const first = await service.call('remember', rememberArguments({ text: 'Old fact.' }));
  assert.equal(first.entities[0].name, 'Kebun');
  assert.deepEqual(first.entities[0].observations, ['Old fact.']);
  const original = first.assertions.find((item) => item.kind === 'observation.add');
  assert.deepEqual(original.provenance, PROVENANCE);
  assert.equal((await store.pending()).length, 2);

  const corrected = await service.call('remember', rememberArguments({ text: 'New verified fact.', supersedes: [original.eventId] }));
  assert.deepEqual(corrected.entities[0].observations, ['New verified fact.']);
  assert.equal((await store.readEvents()).length, 3, 'correction preserves the immutable original event');
  assert.equal((await store.pending()).length, 3);
  await service.call('remember', rememberArguments({ text: 'New verified fact.' }));
  assert.equal((await store.readEvents()).length, 3, 'identical remember is idempotent');
});

test('legacy create_entities does not add observations or change types when a name already exists', async (t) => {
  const { store, service } = await serviceFixture(t);
  const args = {
    scope: SCOPE, provenance: PROVENANCE,
    entities: [{ name: 'Kebun', entityType: 'project', observations: ['Original.'] }],
  };
  const created = await service.call('create_entities', args);
  assert.equal(created.length, 1);
  const before = await store.exportBackup();

  const result = await service.call('create_entities', {
    ...args, entities: [{ name: 'Kebun', entityType: 'different', observations: ['Must not be added.'] }],
  });
  assert.deepEqual(result, []);
  assert.deepEqual(await store.exportBackup(), before);
  const graph = await service.call('read_graph', { scope: SCOPE });
  assert.equal(graph.entities[0].entityType, 'project');
  assert.deepEqual(graph.entities[0].observations, ['Original.']);
});

test('legacy relation and observation tools deduplicate additions and expose scoped search/open results', async (t) => {
  const { service } = await serviceFixture(t);
  await service.call('create_entities', {
    scope: SCOPE, provenance: PROVENANCE,
    entities: [
      { name: 'Kebun', entityType: 'project', observations: [] },
      { name: 'NixOS', entityType: 'operating-system', observations: [] },
    ],
  });
  const edge = { from: 'Kebun', to: 'NixOS', relationType: 'uses' };
  assert.equal((await service.call('create_relations', { scope: SCOPE, provenance: PROVENANCE, relations: [edge, edge] })).length, 1);
  assert.deepEqual(await service.call('create_relations', { scope: SCOPE, provenance: PROVENANCE, relations: [edge] }), []);
  const added = await service.call('add_observations', {
    scope: SCOPE, provenance: PROVENANCE,
    observations: [{ entityName: 'Kebun', observations: ['Managed declaratively.', 'Managed declaratively.'] }],
  });
  assert.deepEqual(added, [{ entityName: 'Kebun', addedObservations: ['Managed declaratively.'] }]);
  await service.call('remember', rememberArguments({ scope: OTHER_SCOPE, name: 'SecretOtherScope', text: 'Not returned.' }));

  const search = await service.call('search_nodes', { scope: SCOPE, query: 'DECLARATIVELY' });
  assert.deepEqual(search.entities.map((item) => item.name), ['Kebun']);
  assert.deepEqual(search.relations, [], 'search must not include unrelated endpoints');
  const opened = await service.call('open_nodes', { scope: SCOPE, names: ['NixOS', 'Kebun'] });
  assert.deepEqual(opened.entities.map((item) => item.name), ['Kebun', 'NixOS']);
  assert.equal(opened.relations.length, 1);
  assert.equal(opened.assertions.every((item) => item.scope === SCOPE), true);
  assert.deepEqual((await service.call('search_nodes', { scope: SCOPE, query: 'SecretOtherScope' })).entities, []);
});

test('all tools require explicit scope; mutators require strict provenance and reject invented or foreign correction targets', async (t) => {
  const { service, store } = await serviceFixture(t);
  const valid = rememberArguments();
  const { scope: omittedScope, ...noScope } = valid;
  const { provenance: omittedProvenance, ...noProvenance } = valid;
  void omittedScope;
  void omittedProvenance;
  const invalid = [
    ['remember', noScope],
    ['remember', noProvenance],
    ['remember', { ...valid, extra: true }],
    ['remember', { ...valid, provenance: { source: 'unverified' } }],
    ['remember', { ...valid, scope: 'global:all' }],
    ['remember', { ...valid, supersedes: [uuid(300)] }],
    ['read_graph', {}],
    ['search_nodes', { query: 'Kebun' }],
    ['open_nodes', { names: ['Kebun'] }],
    ['delete_entities', { scope: SCOPE, entityNames: ['Kebun'] }],
    ['delete_relations', { scope: SCOPE, relations: [] }],
    ['delete_observations', { scope: SCOPE, deletions: [] }],
    ['unknown_tool', { scope: SCOPE }],
    ['__proto__', { scope: SCOPE }],
  ];
  for (const [tool, args] of invalid) {
    await assert.rejects(service.call(tool, args), `${tool} must reject invalid arguments`);
    assert.deepEqual(await store.readEvents(), []);
    assert.deepEqual(await store.pending(), []);
  }
  const foreignScope = await service.call('remember', rememberArguments({ scope: OTHER_SCOPE }));
  const foreignId = foreignScope.assertions.find((item) => item.kind === 'observation.add').eventId;
  const before = await store.exportBackup();
  await assert.rejects(service.call('remember', { ...valid, supersedes: [foreignId] }));
  assert.deepEqual(await store.exportBackup(), before);
});

test('a failed multi-entity mutation leaves neither partial observations nor orphaned outbox records', async (t) => {
  const { service, store } = await serviceFixture(t);
  await service.call('remember', rememberArguments());
  const before = await store.exportBackup();

  await assert.rejects(service.call('add_observations', {
    scope: SCOPE, provenance: PROVENANCE,
    observations: [
      { entityName: 'Kebun', observations: ['Must roll back.'] },
      { entityName: 'Does not exist', observations: ['Cannot add.'] },
    ],
  }));
  assert.deepEqual(await store.exportBackup(), before);
  await assert.rejects(service.call('create_entities', {
    scope: SCOPE, provenance: PROVENANCE,
    entities: Array.from({ length: 100 }, (_, index) => ({ name: `Batch ${index}`, entityType: 'test', observations: ['Would exceed the 100-event mutation limit.'] })),
  }));
  assert.deepEqual(await store.exportBackup(), before);
});

test('simultaneous local callers serialize the ensure-entity/read/append boundary without nested PGlite transactions', async (t) => {
  const { service, store } = await serviceFixture(t);

  await Promise.all(Array.from({ length: 8 }, (_, index) => service.call('remember', rememberArguments({ text: `Concurrent fact ${index}.` }))));

  const events = await store.readEvents();
  assert.equal(events.filter((item) => item.kind === 'entity.add').length, 1);
  assert.equal(events.filter((item) => item.kind === 'observation.add').length, 8);
  assert.equal((await service.call('read_graph', { scope: SCOPE })).entities[0].observations.length, 8);
  assert.equal((await store.status()).pendingCount, 9);
});

test('an export racing an atomic remember sees the complete mutation or none of it, never half an entity/outbox pair', async (t) => {
  const { service, store } = await serviceFixture(t);
  for (let index = 0; index < 4; index += 1) {
    const name = `Snapshot ${index}`;
    const [backup] = await Promise.all([
      store.exportBackup(),
      service.call('remember', rememberArguments({ name, text: `Fact ${index}.` })),
    ]);
    const entityEvents = backup.events.filter((event) => event.kind === 'entity.add' && event.data.name === name);
    const observations = backup.events.filter((event) => event.kind === 'observation.add' && event.data.entity === name);
    assert.equal(entityEvents.length, observations.length);
    assert.ok(entityEvents.length === 0 || entityEvents.length === 1);
    assert.deepEqual([...backup.delivery.pendingIds].sort(), backup.events.map((event) => event.eventId).sort());
  }
});

test('delete_observations retracts only currently observed IDs; a delayed concurrent assertion of the same text survives', async (t) => {
  const { service, store } = await serviceFixture(t);
  const first = await service.call('remember', rememberArguments({ text: 'Concurrent fact.' }));
  const observedId = first.assertions.find((item) => item.kind === 'observation.add').eventId;

  const deleted = await service.call('delete_observations', {
    scope: SCOPE, provenance: PROVENANCE,
    deletions: [{ entityName: 'Kebun', observations: ['Concurrent fact.'] }],
  });
  assert.deepEqual(deleted.retractedIds, [observedId]);
  const tombstone = (await store.readEvents()).find((item) => item.kind === 'retract');
  assert.deepEqual(tombstone.data.targets, [observedId]);
  assert.equal(tombstone.data.reason, 'deletion');
  await store.applyPullPage(pullPage([
    observation(401, 'Concurrent fact.', [], { actorId: ACTOR_B }),
  ], uuid(490)));
  const graph = await service.call('read_graph', { scope: SCOPE });
  assert.deepEqual(graph.entities[0].observations, ['Concurrent fact.']);
  assert.equal(graph.assertions.some((item) => item.eventId === observedId), false);
  assert.equal(graph.assertions.some((item) => item.eventId === uuid(401)), true);
});

test('delete_relations and delete_entities remove observed incident assertions only within the selected scope', async (t) => {
  const { service, store } = await serviceFixture(t);
  await service.call('create_entities', {
    scope: SCOPE, provenance: PROVENANCE,
    entities: [{ name: 'Kebun', entityType: 'project', observations: ['Fact.'] }, { name: 'NixOS', entityType: 'operating-system', observations: [] }],
  });
  const edge = { from: 'Kebun', to: 'NixOS', relationType: 'uses' };
  await service.call('create_relations', { scope: SCOPE, provenance: PROVENANCE, relations: [edge] });
  await service.call('remember', rememberArguments({ scope: OTHER_SCOPE }));

  await service.call('delete_relations', { scope: SCOPE, provenance: PROVENANCE, relations: [edge] });
  assert.deepEqual((await service.call('read_graph', { scope: SCOPE })).relations, []);
  await service.call('create_relations', { scope: SCOPE, provenance: PROVENANCE, relations: [edge] });
  await service.call('delete_entities', { scope: SCOPE, provenance: PROVENANCE, entityNames: ['Kebun'] });
  const graph = await service.call('read_graph', { scope: SCOPE });
  assert.deepEqual(graph.entities.map((item) => item.name), ['NixOS']);
  assert.deepEqual(graph.relations, []);
  assert.equal((await service.call('read_graph', { scope: OTHER_SCOPE })).entities.length, 1);

  await store.applyPullPage(pullPage([entity(501, 'Kebun', 'project', { actorId: ACTOR_B })], uuid(590)));
  assert.equal((await service.call('open_nodes', { scope: SCOPE, names: ['Kebun'] })).entities.length, 1);
});
