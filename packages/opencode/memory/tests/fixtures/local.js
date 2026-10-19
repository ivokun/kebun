import path from 'node:path';
import { LocalStore } from '../../dist/local-store.js';
import { ACCOUNT, ACTOR_A } from './events.js';
import { cleanup, temporaryDirectory } from './resources.js';

export async function localStore(t, options = {}) {
  const directory = await temporaryDirectory(t, 'local');
  const configuration = {
    stateDir: path.join(directory, 'state'),
    accountId: ACCOUNT,
    actorId: ACTOR_A,
    ...options,
  };
  let current = await LocalStore.open(configuration);
  cleanup(t, async () => {
    const closing = current;
    current = undefined;
    if (closing) await closing.close();
  });
  return {
    directory,
    configuration,
    get store() { return current; },
    async close() {
      const closing = current;
      current = undefined;
      if (closing) await closing.close();
    },
    async restart() {
      await this.close();
      current = await LocalStore.open(configuration);
      return current;
    },
  };
}

export function eventIds(events) {
  return events.map((item) => item.eventId).sort();
}

export function pullPage(events, epoch, start = 1, hasMore = false) {
  return {
    protocol: 1,
    cursor: { epoch, position: String(start + events.length - 1) },
    events: events.map((item, index) => ({ position: String(start + index), event: item })),
    hasMore,
  };
}
