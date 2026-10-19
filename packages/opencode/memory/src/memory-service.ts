import { randomUUID } from "node:crypto";
import { z } from "zod";
import { MemoryError } from "./errors.js";
import { reduceGraph, type MemoryGraph } from "./graph.js";
import { LocalStore } from "./local-store.js";
import {
  enforceJsonLimit, MAX_ARRAY_ITEMS, MAX_EVENTS, memoryEventSchema, nameSchema, observationTextSchema,
  provenanceSchema, scopeSchema, uuidSchema,
  type AdditionEvent, type MemoryEvent, type Principal, type Provenance,
} from "./protocol.js";

const names = z.array(nameSchema).max(MAX_ARRAY_ITEMS);
const texts = z.array(observationTextSchema).max(MAX_ARRAY_ITEMS);
const relationSchema = z.strictObject({ from: nameSchema, to: nameSchema, relationType: nameSchema });
const mutation = { scope: scopeSchema, provenance: provenanceSchema };
export const toolSchemas = {
  create_entities: z.strictObject({ ...mutation, entities: z.array(z.strictObject({
    name: nameSchema, entityType: nameSchema, observations: texts,
  })).max(MAX_ARRAY_ITEMS) }),
  create_relations: z.strictObject({ ...mutation, relations: z.array(relationSchema).max(MAX_ARRAY_ITEMS) }),
  add_observations: z.strictObject({ ...mutation, observations: z.array(z.strictObject({
    entityName: nameSchema, observations: texts,
  })).max(MAX_ARRAY_ITEMS) }),
  delete_entities: z.strictObject({ ...mutation, entityNames: names }),
  delete_relations: z.strictObject({ ...mutation, relations: z.array(relationSchema).max(MAX_ARRAY_ITEMS) }),
  delete_observations: z.strictObject({ ...mutation, deletions: z.array(z.strictObject({
    entityName: nameSchema, observations: texts,
  })).max(MAX_ARRAY_ITEMS) }),
  remember: z.strictObject({
    ...mutation, name: nameSchema, entityType: nameSchema, text: observationTextSchema,
    supersedes: z.array(uuidSchema).max(MAX_ARRAY_ITEMS).refine((ids) => new Set(ids).size === ids.length).optional(),
  }),
  read_graph: z.strictObject({ scope: scopeSchema }),
  search_nodes: z.strictObject({ scope: scopeSchema, query: z.string().min(1).max(1024) }),
  open_nodes: z.strictObject({ scope: scopeSchema, names }),
};
export type ToolName = keyof typeof toolSchemas;
export const toolNames = Object.keys(toolSchemas).filter((name): name is ToolName => name in toolSchemas);
export const readOnlyTools = new Set<string>(["read_graph", "search_nodes", "open_nodes"]);
const graphEntitySchema = z.strictObject({
  name: nameSchema, entityType: nameSchema.nullable(), observations: z.array(observationTextSchema), assertionIds: z.array(uuidSchema),
});
const graphRelationSchema = relationSchema.extend({ assertionIds: z.array(uuidSchema) }).strict();
export const graphSchema = z.strictObject({
  entities: z.array(graphEntitySchema), relations: z.array(graphRelationSchema),
  assertions: z.array(memoryEventSchema).refine((events) => events.every((event) => event.kind !== "retract")),
  conflicts: z.array(z.strictObject({ entity: nameSchema, entityTypes: z.array(nameSchema).min(2), assertionIds: z.array(uuidSchema) })),
});

export function validateToolResult(tool: ToolName, value: unknown): unknown {
  if (readOnlyTools.has(tool) || tool === "remember") return graphSchema.parse(value);
  if (tool === "create_entities") return z.array(graphEntitySchema).parse(value);
  if (tool === "create_relations") return z.array(graphRelationSchema).parse(value);
  if (tool === "add_observations") return z.array(z.strictObject({ entityName: nameSchema, addedObservations: texts })).parse(value);
  return z.strictObject({ retractedIds: z.array(uuidSchema) }).parse(value);
}

function event(
  identity: Principal, scope: string, provenance: Provenance,
  addition: { kind: "entity.add"; data: { name: string; entityType: string } }
    | { kind: "observation.add"; data: { entity: string; text: string; supersedes: string[] } }
    | { kind: "relation.add"; data: { from: string; to: string; relationType: string } }
    | { kind: "retract"; data: { targets: string[]; reason: "correction" | "deletion" } },
): MemoryEvent {
  return {
    version: 1, eventId: randomUUID(), ...identity, scope, recordedAt: new Date().toISOString(), provenance, ...addition,
  };
}

function selectedGraph(graph: MemoryGraph, names: ReadonlySet<string>): MemoryGraph {
  return {
    entities: graph.entities.filter((entity) => names.has(entity.name)),
    relations: graph.relations.filter((relation) => names.has(relation.from) && names.has(relation.to)),
    assertions: graph.assertions.filter((assertion) => assertion.kind === "entity.add" ? names.has(assertion.data.name)
      : assertion.kind === "observation.add" ? names.has(assertion.data.entity)
        : names.has(assertion.data.from) && names.has(assertion.data.to)),
    conflicts: graph.conflicts.filter((conflict) => names.has(conflict.entity)),
  };
}

/** Curated, scoped graph operations. No direct append or unrestricted tombstone MCP tool exists. */
export class MemoryService {
  constructor(private readonly store: LocalStore) {}

  async call(tool: string, arguments_: unknown): Promise<unknown> {
    enforceJsonLimit(arguments_);
    if (!(tool in toolSchemas) || !Object.hasOwn(toolSchemas, tool)) {
      throw new MemoryError("unknown_tool", 400, "Unknown memory tool.");
    }
    switch (tool) {
      case "read_graph": {
        const args = toolSchemas.read_graph.parse(arguments_);
        return reduceGraph(await this.store.readEvents(), args.scope);
      }
      case "search_nodes": {
        const args = toolSchemas.search_nodes.parse(arguments_);
        const graph = reduceGraph(await this.store.readEvents(), args.scope);
        const query = args.query.normalize("NFC").toLowerCase();
        const matches = (text: string): boolean => text.toLowerCase().includes(query);
        const selected = new Set<string>();
        // Concurrent assertions remain searchable even if their entity declaration
        // was observed-removed; recall must not invent replacement declarations.
        for (const assertion of graph.assertions) {
          if (assertion.kind === "entity.add") {
            if (matches(assertion.data.name) || matches(assertion.data.entityType)) selected.add(assertion.data.name);
          } else if (assertion.kind === "observation.add") {
            if (matches(assertion.data.entity) || matches(assertion.data.text)) selected.add(assertion.data.entity);
          } else if (matches(assertion.data.from) || matches(assertion.data.to) || matches(assertion.data.relationType)) {
            selected.add(assertion.data.from);
            selected.add(assertion.data.to);
          }
        }
        return selectedGraph(graph, selected);
      }
      case "open_nodes": {
        const args = toolSchemas.open_nodes.parse(arguments_);
        return selectedGraph(reduceGraph(await this.store.readEvents(), args.scope), new Set(args.names));
      }
      case "create_entities": {
        const args = toolSchemas.create_entities.parse(arguments_);
        return this.store.mutate((existing, identity) => {
          const graph = reduceGraph(existing, args.scope);
          const present = new Set(graph.entities.map((entity) => entity.name));
          const additions: MemoryEvent[] = [];
          const created = new Set<string>();
          for (const entity of args.entities) {
            // An existing name is a complete no-op, including its supplied observations.
            if (present.has(entity.name)) continue;
            present.add(entity.name);
            created.add(entity.name);
            additions.push(event(identity, args.scope, args.provenance, {
              kind: "entity.add", data: { name: entity.name, entityType: entity.entityType },
            }));
            for (const text of new Set(entity.observations)) {
              additions.push(event(identity, args.scope, args.provenance, {
                kind: "observation.add", data: { entity: entity.name, text, supersedes: [] },
              }));
            }
          }
          return { events: additions, result: reduceGraph([...existing, ...additions], args.scope).entities.filter((entity) => created.has(entity.name)) };
        });
      }
      case "create_relations": {
        const args = toolSchemas.create_relations.parse(arguments_);
        return this.store.mutate((existing, identity) => {
          const graph = reduceGraph(existing, args.scope);
          const key = (relation: { from: string; to: string; relationType: string }) => JSON.stringify([relation.from, relation.to, relation.relationType]);
          const present = new Set(graph.relations.map(key));
          const additions: MemoryEvent[] = [];
          const created = new Set<string>();
          for (const relation of args.relations) {
            const id = key(relation);
            if (present.has(id)) continue;
            present.add(id);
            created.add(id);
            additions.push(event(identity, args.scope, args.provenance, { kind: "relation.add", data: relation }));
          }
          return { events: additions, result: reduceGraph([...existing, ...additions], args.scope).relations.filter((relation) => created.has(key(relation))) };
        });
      }
      case "add_observations": {
        const args = toolSchemas.add_observations.parse(arguments_);
        return this.store.mutate((existing, identity) => {
          const graph = reduceGraph(existing, args.scope);
          const present = new Map(graph.entities.map((entity) => [entity.name, new Set(entity.observations)]));
          const additions: MemoryEvent[] = [];
          const result: { entityName: string; addedObservations: string[] }[] = [];
          for (const entry of args.observations) {
            const observations = present.get(entry.entityName);
            if (!observations) throw new MemoryError("entity_not_found", 400, "Observation entity does not exist in this scope.");
            const addedObservations: string[] = [];
            for (const text of entry.observations) {
              if (observations.has(text)) continue;
              observations.add(text);
              addedObservations.push(text);
              additions.push(event(identity, args.scope, args.provenance, {
                kind: "observation.add", data: { entity: entry.entityName, text, supersedes: [] },
              }));
            }
            result.push({ entityName: entry.entityName, addedObservations });
          }
          return { events: additions, result };
        });
      }
      case "remember": {
        const args = toolSchemas.remember.parse(arguments_);
        return this.store.mutate((existing, identity) => {
          const graph = reduceGraph(existing, args.scope);
          const entity = graph.entities.find((candidate) => candidate.name === args.name);
          const additions: MemoryEvent[] = [];
          if (!entity) additions.push(event(identity, args.scope, args.provenance, {
            kind: "entity.add", data: { name: args.name, entityType: args.entityType },
          }));
          const supersedes = args.supersedes ?? [];
          // A correction may only suppress observed assertions for this exact entity.
          for (const id of supersedes) {
            if (!graph.assertions.some((assertion) => assertion.eventId === id
              && assertion.kind === "observation.add" && assertion.data.entity === args.name)) {
              throw new MemoryError("invalid_correction", 400, "Correction target is not an active observation for this entity.");
            }
          }
          if (supersedes.length > 0 || !entity?.observations.includes(args.text)) {
            additions.push(event(identity, args.scope, args.provenance, {
              kind: "observation.add", data: { entity: args.name, text: args.text, supersedes },
            }));
          }
          return { events: additions, result: selectedGraph(reduceGraph([...existing, ...additions], args.scope), new Set([args.name])) };
        });
      }
      case "delete_entities": {
        const args = toolSchemas.delete_entities.parse(arguments_);
        const selected = new Set(args.entityNames);
        return this.retract(args.scope, args.provenance, (assertion) =>
          assertion.kind === "entity.add" ? selected.has(assertion.data.name)
            : assertion.kind === "observation.add" ? selected.has(assertion.data.entity)
              : selected.has(assertion.data.from) || selected.has(assertion.data.to));
      }
      case "delete_relations": {
        const args = toolSchemas.delete_relations.parse(arguments_);
        return this.retract(args.scope, args.provenance, (assertion) => assertion.kind === "relation.add"
          && args.relations.some((relation) => relation.from === assertion.data.from && relation.to === assertion.data.to
            && relation.relationType === assertion.data.relationType));
      }
      case "delete_observations": {
        const args = toolSchemas.delete_observations.parse(arguments_);
        return this.retract(args.scope, args.provenance, (assertion) => assertion.kind === "observation.add"
          && args.deletions.some((deletion) => deletion.entityName === assertion.data.entity && deletion.observations.includes(assertion.data.text)));
      }
      default: throw new MemoryError("unknown_tool", 400, "Unknown memory tool.");
    }
  }

  private async retract(scope: string, provenance: Provenance, predicate: (assertion: AdditionEvent) => boolean): Promise<unknown> {
    return this.store.mutate((existing, identity) => {
      const ids = reduceGraph(existing, scope).assertions.filter(predicate).map((assertion) => assertion.eventId);
      const additions: MemoryEvent[] = [];
      for (let index = 0; index < ids.length; index += MAX_ARRAY_ITEMS) {
        additions.push(event(identity, scope, provenance, {
          kind: "retract", data: { targets: ids.slice(index, index + MAX_ARRAY_ITEMS), reason: "deletion" },
        }));
      }
      if (additions.length > MAX_EVENTS) throw new MemoryError("payload_too_large", 413, "Deletion exceeds the mutation limit; use smaller scoped batches.");
      return { events: additions, result: { retractedIds: ids } };
    });
  }
}
