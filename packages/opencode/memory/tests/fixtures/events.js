export const ACCOUNT = '6f67358f-8bbf-48d1-a48f-ec40c3c3fd8d';
export const ACTOR_A = 'efe55bc9-fa10-4af0-b29b-217338fe7508';
export const ACTOR_B = '90241cd7-cf71-4927-8ff4-62ecb02ffdca';
export const OTHER_ACCOUNT = '75666ca5-b051-40d8-9124-06af5b860c40';
export const SCOPE = 'project:memory-tests';
export const OTHER_SCOPE = 'topic:other-tests';
export const INSTANT = '2026-10-19T10:00:00.000Z';
export const PROVENANCE = {
  source: 'test fixture: reviewed configuration',
  verifiedAt: INSTANT,
  revision: 'fixture-revision-1',
};

export function uuid(number) {
  return `00000000-0000-4000-8000-${number.toString(16).padStart(12, '0')}`;
}

export function event(number, kind, data, overrides = {}) {
  return {
    version: 1,
    eventId: uuid(number),
    accountId: ACCOUNT,
    actorId: ACTOR_A,
    scope: SCOPE,
    recordedAt: INSTANT,
    provenance: { ...PROVENANCE },
    kind,
    data,
    ...overrides,
  };
}

export function entity(number, name = 'Kebun', entityType = 'project', overrides = {}) {
  return event(number, 'entity.add', { name, entityType }, overrides);
}

export function observation(number, text, supersedes = [], overrides = {}) {
  return event(number, 'observation.add', {
    entity: 'Kebun',
    text,
    supersedes,
  }, overrides);
}

export function relation(number, from = 'Kebun', to = 'NixOS', overrides = {}) {
  return event(number, 'relation.add', { from, to, relationType: 'uses' }, overrides);
}

export function retraction(number, targets, reason = 'correction', overrides = {}) {
  return event(number, 'retract', { targets, reason }, overrides);
}

export function principal(actorId = ACTOR_A, accountId = ACCOUNT) {
  return { accountId, actorId };
}

export function rememberArguments(overrides = {}) {
  return {
    scope: SCOPE,
    name: 'Kebun',
    entityType: 'project',
    text: 'Uses declarative host configuration.',
    provenance: { ...PROVENANCE },
    ...overrides,
  };
}

export function permutations(values) {
  if (values.length <= 1) return [values];
  return values.flatMap((value, index) => permutations([
    ...values.slice(0, index),
    ...values.slice(index + 1),
  ]).map((rest) => [value, ...rest]));
}
