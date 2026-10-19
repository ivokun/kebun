import { z } from "zod";
import { MemoryError } from "./errors.js";

export const MAX_EVENTS = 100;
export const MAX_PUSH_BYTES = 1024 * 1024;
export const MAX_SYNC_RESPONSE_BYTES = 2 * 1024 * 1024;
export const MAX_BACKUP_BYTES = 64 * 1024 * 1024;
export const MAX_LOCAL_REQUEST_BYTES = MAX_BACKUP_BYTES;
export const MAX_ARRAY_ITEMS = 100;

// With Unicode mode, surrogate pairs are code points outside this range; only
// unpaired surrogates (and NUL, also unsupported by PostgreSQL jsonb) are rejected.
const isPersistableText = (value: string): boolean => !/[\u0000\uD800-\uDFFF]/u.test(value);

export const uuidSchema = z.uuid().transform((value) => value.toLowerCase());
export const positionSchema = z.string().regex(/^(0|[1-9][0-9]*)$/).max(40);
export const scopeSchema = z.string().max(128).regex(/^(project|topic|user):[a-z0-9][a-z0-9._/-]*$/);
export const nameSchema = z.string().refine(isPersistableText).transform((value) => value.trim().normalize("NFC"))
  .pipe(z.string().min(1).max(200).refine((value) => !/[\u0000-\u001f\u007f]/u.test(value)));
// Names have one normalized representation at every validation boundary. All
// immutable comparisons use these validated values, never raw JSON key order.
export const eventNameSchema = nameSchema;
export const utcIsoSchema = z.iso.datetime({ offset: false });
const boundedText = (maxBytes: number) => z.string().min(1)
  .refine((value) => Buffer.byteLength(value, "utf8") <= maxBytes)
  .refine(isPersistableText);
export const observationTextSchema = boundedText(8 * 1024);
export const provenanceSchema = z.strictObject({
  source: boundedText(2 * 1024),
  verifiedAt: utcIsoSchema,
  revision: z.string().min(1).max(128).refine(isPersistableText).optional(),
});
export type Provenance = z.infer<typeof provenanceSchema>;

const idsSchema = z.array(uuidSchema).max(MAX_ARRAY_ITEMS)
  .refine((ids) => new Set(ids).size === ids.length);
const eventBase = {
  version: z.literal(1),
  eventId: uuidSchema,
  accountId: uuidSchema,
  actorId: uuidSchema,
  scope: scopeSchema,
  recordedAt: utcIsoSchema,
  provenance: provenanceSchema,
};
export const memoryEventSchema = z.discriminatedUnion("kind", [
  z.strictObject({
    ...eventBase, kind: z.literal("entity.add"),
    data: z.strictObject({ name: eventNameSchema, entityType: eventNameSchema }),
  }),
  z.strictObject({
    ...eventBase, kind: z.literal("observation.add"),
    data: z.strictObject({ entity: eventNameSchema, text: observationTextSchema, supersedes: idsSchema }),
  }),
  z.strictObject({
    ...eventBase, kind: z.literal("relation.add"),
    data: z.strictObject({ from: eventNameSchema, to: eventNameSchema, relationType: eventNameSchema }),
  }),
  z.strictObject({
    ...eventBase, kind: z.literal("retract"),
    data: z.strictObject({ targets: idsSchema.min(1), reason: z.enum(["correction", "deletion"]) }),
  }),
]);
export type MemoryEvent = z.infer<typeof memoryEventSchema>;
export type AdditionEvent = Exclude<MemoryEvent, { kind: "retract" }>;
export const principalSchema = z.strictObject({ accountId: uuidSchema, actorId: uuidSchema });
export type Principal = z.infer<typeof principalSchema>;
export const cursorSchema = z.strictObject({ epoch: uuidSchema, position: positionSchema });
export type Cursor = z.infer<typeof cursorSchema>;
export const pushRequestSchema = z.strictObject({
  protocol: z.literal(1), epoch: uuidSchema, events: z.array(memoryEventSchema).max(MAX_EVENTS),
});
export type PushRequest = z.infer<typeof pushRequestSchema>;
export const pushResponseSchema = z.strictObject({ protocol: z.literal(1), epoch: uuidSchema, acceptedIds: idsSchema });
export type PushResponse = z.infer<typeof pushResponseSchema>;
export const pullRequestSchema = z.strictObject({
  protocol: z.literal(1), cursor: cursorSchema.nullable(), limit: z.number().int().min(1).max(MAX_EVENTS),
});
export type PullRequest = z.infer<typeof pullRequestSchema>;
export const pullResponseSchema = z.strictObject({
  protocol: z.literal(1), cursor: cursorSchema,
  events: z.array(z.strictObject({ position: positionSchema, event: memoryEventSchema })).max(MAX_EVENTS),
  hasMore: z.boolean(),
});
export type PullResponse = z.infer<typeof pullResponseSchema>;
export const serverInfoSchema = z.strictObject({
  protocol: z.literal(1), accountId: uuidSchema, epoch: uuidSchema, headPosition: positionSchema,
});
export type ServerInfo = z.infer<typeof serverInfoSchema>;
export const memoryBackupSchema = z.strictObject({
  formatVersion: z.literal(1),
  accountId: uuidSchema,
  actorId: uuidSchema,
  events: z.array(memoryEventSchema),
  delivery: z.strictObject({ pendingIds: z.array(uuidSchema) }),
  cursor: cursorSchema.nullable(),
  syncEpoch: uuidSchema.nullable(),
});
export type MemoryBackup = z.infer<typeof memoryBackupSchema>;
export const localStatusSchema = z.strictObject({
  accountId: uuidSchema, actorId: uuidSchema,
  durability: z.literal("best-effort"),
  eventCount: z.number().int().nonnegative(), pendingCount: z.number().int().nonnegative(),
  cursor: cursorSchema.nullable(), syncEpoch: uuidSchema.nullable(),
});
export const syncStatusSchema = z.strictObject({
  enabled: z.boolean(), running: z.boolean(),
  lastAttemptAt: utcIsoSchema.nullable(), lastSuccessAt: utcIsoSchema.nullable(), nextAttemptAt: utcIsoSchema.nullable(),
  lastError: z.strictObject({ code: z.string().min(1).max(100), message: z.string().max(200) }).nullable(),
});
export const daemonStatusSchema = localStatusSchema.extend({ sync: syncStatusSchema }).strict();
export const importResultSchema = z.strictObject({ importedCount: z.number().int().nonnegative() });

// PascalCase aliases make schemas as discoverable as their corresponding public types.
export const MemoryEventSchema = memoryEventSchema;
export const ProvenanceSchema = provenanceSchema;
export const PrincipalSchema = principalSchema;
export const CursorSchema = cursorSchema;
export const PushRequestSchema = pushRequestSchema;
export const PushResponseSchema = pushResponseSchema;
export const PullRequestSchema = pullRequestSchema;
export const PullResponseSchema = pullResponseSchema;
export const ServerInfoSchema = serverInfoSchema;
export const MemoryBackupSchema = memoryBackupSchema;

/** Immutable equality is structural JSON equality, never object insertion order. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    return `{${Object.keys(value).sort().map((key) => {
      const field: unknown = Reflect.get(value, key);
      return `${JSON.stringify(key)}:${canonicalJson(field)}`;
    }).join(",")}}`;
  }
  throw new MemoryError("invalid_json", 400, "Value is not JSON.");
}

export function enforceJsonLimit(value: unknown, limit = MAX_PUSH_BYTES): void {
  let serialized: string | undefined;
  try { serialized = JSON.stringify(value); }
  catch { throw new MemoryError("invalid_json", 400, "Value is not JSON."); }
  if (serialized === undefined) throw new MemoryError("invalid_json", 400, "Value is not JSON.");
  if (Buffer.byteLength(serialized, "utf8") > limit) {
    throw new MemoryError("payload_too_large", 413, "Payload exceeds the size limit.");
  }
}

/** Version checks precede schema validation so remote protocol negotiation is explicit. */
export function requireProtocol(value: unknown): void {
  if (typeof value === "object" && value !== null && "protocol" in value && value.protocol !== 1) {
    throw new MemoryError("unsupported_protocol", 426, "Unsupported protocol version.");
  }
}
