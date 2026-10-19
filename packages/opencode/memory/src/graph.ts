import { collision } from "./errors.js";
import { canonicalJson, memoryEventSchema, scopeSchema, type AdditionEvent, type MemoryEvent } from "./protocol.js";

export interface GraphEntity {
  name: string;
  entityType: string | null;
  observations: string[];
  assertionIds: string[];
}
export interface GraphRelation {
  from: string;
  to: string;
  relationType: string;
  assertionIds: string[];
}
export interface GraphConflict {
  entity: string;
  entityTypes: string[];
  assertionIds: string[];
}
export interface MemoryGraph {
  entities: GraphEntity[];
  relations: GraphRelation[];
  assertions: AdditionEvent[];
  conflicts: GraphConflict[];
}

const compare = (left: string, right: string): number => left < right ? -1 : left > right ? 1 : 0;

/**
 * This is an observed-remove graph, not last-write-wins. Metadata timestamps never
 * select a winner. Suppression is scoped by both account and scope; tombstones
 * also suppress additions that have not arrived yet, but never other tombstones.
 */
export function reduceGraph(events: readonly MemoryEvent[], scope: string): MemoryGraph {
  const selectedScope = scopeSchema.parse(scope);
  const unique = new Map<string, MemoryEvent>();
  for (const raw of events) {
    const event = memoryEventSchema.parse(raw);
    const previous = unique.get(event.eventId);
    if (previous && canonicalJson(previous) !== canonicalJson(event)) throw collision();
    unique.set(event.eventId, event);
  }
  const scoped = [...unique.values()].filter((event) => event.scope === selectedScope);
  const suppressed = new Set<string>();
  for (const event of scoped) {
    const targets = event.kind === "retract" ? event.data.targets
      : event.kind === "observation.add" ? event.data.supersedes : [];
    for (const id of targets) suppressed.add(`${event.accountId}:${id}`);
  }
  const assertions = scoped.filter((event): event is AdditionEvent =>
    event.kind !== "retract" && !suppressed.has(`${event.accountId}:${event.eventId}`),
  ).sort((a, b) => compare(a.eventId, b.eventId));

  const entityNames = new Set<string>();
  for (const event of assertions) {
    if (event.kind === "entity.add") entityNames.add(event.data.name);
  }
  const entities: GraphEntity[] = [];
  const conflicts: GraphConflict[] = [];
  for (const name of [...entityNames].sort(compare)) {
    const additions = assertions.filter((event) => event.kind === "entity.add" && event.data.name === name);
    const types = [...new Set(additions.flatMap((event) => event.kind === "entity.add" ? [event.data.entityType] : []))].sort(compare);
    const observations = assertions.filter((event) => event.kind === "observation.add" && event.data.entity === name);
    entities.push({
      name,
      entityType: types.length === 1 ? types[0] ?? null : null,
      observations: [...new Set(observations.flatMap((event) => event.kind === "observation.add" ? [event.data.text] : []))].sort(compare),
      assertionIds: [...additions, ...observations].map((event) => event.eventId).sort(compare),
    });
    if (types.length > 1) conflicts.push({ entity: name, entityTypes: types, assertionIds: additions.map((event) => event.eventId) });
  }

  const relationGroups = new Map<string, GraphRelation>();
  for (const event of assertions) {
    if (event.kind !== "relation.add") continue;
    const { from, to, relationType } = event.data;
    const key = canonicalJson([from, to, relationType]);
    const relation = relationGroups.get(key) ?? { from, to, relationType, assertionIds: [] };
    relation.assertionIds.push(event.eventId);
    relationGroups.set(key, relation);
  }
  const relations = [...relationGroups.entries()].sort(([a], [b]) => compare(a, b)).map(([, relation]) => relation);
  return { entities, relations, assertions, conflicts };
}
