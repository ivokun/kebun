import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { cleanEnvironment, cleanup, run, temporaryDirectory } from './resources.js';

// This helper never reads PG* defaults, an existing data directory, or a live DB.
// Unix sockets in separate 0700 directories may safely reuse the same port.
export async function ephemeralPostgres(t) {
  const binary = (name) => process.env.MEMORY_TEST_POSTGRES_BIN
    ? path.join(process.env.MEMORY_TEST_POSTGRES_BIN, name) : name;
  const { stdout: version } = await run(binary('postgres'), ['--version']);
  assert.match(version, /\b16\./, 'integration fixtures require PostgreSQL 16');
  const directory = await temporaryDirectory(t, 'pg');
  const dataDir = path.join(directory, 'data');
  const socketDir = path.join(directory, 'socket');
  const port = 15432;
  const user = 'memory_test';
  const database = 'postgres';
  await mkdir(socketDir, { mode: 0o700 });
  const env = cleanEnvironment({
    PGHOST: socketDir,
    PGPORT: String(port),
    PGUSER: user,
    PGDATABASE: database,
    PGPASSWORD: '',
    PGPASSFILE: path.join(directory, 'no-password-file'),
    PGSERVICEFILE: path.join(directory, 'no-service-file'),
  });
  // pg runs in this Node process, not only in psql/pg_ctl children. Remove all
  // inherited libpq defaults without reading their values, then pin its fixture.
  for (const key of Object.keys(process.env)) {
    if (key.startsWith('PG')) delete process.env[key];
  }
  for (const [key, value] of Object.entries(env)) {
    if (key.startsWith('PG')) process.env[key] = value;
  }
  await run(binary('initdb'), [
    '--pgdata', dataDir,
    '--username', user,
    '--auth', 'trust',
    '--no-locale',
    '--encoding', 'UTF8',
  ], { env });

  let started = false;
  cleanup(t, async () => {
    if (started) {
      await run(binary('pg_ctl'), [
        '--pgdata', dataDir, '--mode', 'immediate', '--wait', '--timeout', '15', 'stop',
      ], { env });
    }
  });
  // Register cleanup before startup: pg_ctl may time out after postgres starts.
  started = true;
  await run(binary('pg_ctl'), [
    '--pgdata', dataDir,
    '--log', path.join(directory, 'postgres.log'),
    '--wait', '--timeout', '20',
    '--options', [
      `-k '${socketDir}'`, `-p ${port}`,
      "-c listen_addresses=''",
      '-c unix_socket_permissions=0700',
      '-c max_connections=16',
      '-c shared_buffers=16MB',
      '-c fsync=on',
      '-c synchronous_commit=on',
    ].join(' '),
    'start',
  ], { env });

  const databaseUrl = new URL(`postgresql://${user}@localhost:${port}/${database}`);
  databaseUrl.searchParams.set('host', socketDir);
  databaseUrl.searchParams.set('connect_timeout', '5');
  return {
    databaseUrl: databaseUrl.href,
    directory,
    async sql(statement) {
      const result = await run(binary('psql'), [
        '--no-psqlrc', '--no-password', '--tuples-only', '--no-align',
        '--host', socketDir, '--port', String(port),
        '--username', user, '--dbname', database,
        '--set', 'ON_ERROR_STOP=1', '--command', statement,
      ], { env });
      return result.stdout.trim();
    },
  };
}
