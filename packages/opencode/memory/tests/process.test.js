import assert from 'node:assert/strict';
import { mkdir, readFile, rm, stat, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { ACCOUNT, ACTOR_A, SCOPE, rememberArguments } from './fixtures/events.js';
import { daemon, exited, mcpClient, spawnCli, unixRequest } from './fixtures/process.js';
import { cliPath, run, stopChild, temporaryDirectory } from './fixtures/resources.js';

function call(socket, tool, arguments_) {
  return unixRequest(socket, 'POST', '/v1/call', { tool, arguments: arguments_ });
}

test('offline daemon serves concurrent local sessions through its private socket and two MCP stdio bridges', { timeout: 90_000 }, async (t) => {
  const directory = await temporaryDirectory(t, 'offline');
  const owner = await daemon(t, {
    directory,
    extraArgs: ['--sync-url', 'https://memory.example.invalid', '--token-file', path.join(directory, 'missing-token')],
  });
  assert.equal((await stat(owner.stateDir)).mode & 0o777, 0o700);
  assert.equal((await stat(owner.socket)).mode & 0o777, 0o600);
  const initial = await unixRequest(owner.socket, 'GET', '/v1/status');
  assert.equal(initial.body.accountId, ACCOUNT);
  assert.equal(initial.body.actorId, ACTOR_A);
  assert.equal(initial.body.pendingCount, 0);

  const written = await call(owner.socket, 'remember', rememberArguments({ text: 'PRIVATE_TEST_MEMORY_FACT' }));
  assert.equal(written.status, 200);
  const clients = [mcpClient(t, owner.socket), mcpClient(t, owner.socket)];
  await Promise.all(clients.map((client) => client.initialize()));
  const definitions = await clients[0].rpc('tools/list', {});
  const byName = new Map(definitions.tools.map((tool) => [tool.name, tool]));
  for (const name of [
    'create_entities', 'create_relations', 'add_observations', 'delete_entities',
    'delete_relations', 'delete_observations', 'read_graph', 'search_nodes', 'open_nodes', 'remember',
  ]) {
    assert.ok(byName.has(name), `MCP must advertise ${name}`);
    assert.ok(byName.get(name).inputSchema.required.includes('scope'));
  }
  assert.equal(byName.get('search_nodes').annotations.readOnlyHint, true);
  assert.equal(byName.get('remember').annotations.readOnlyHint, false);
  assert.ok(byName.get('remember').inputSchema.required.includes('provenance'));
  const answers = await Promise.all(clients.map((client) => client.rpc('tools/call', {
    name: 'search_nodes', arguments: { scope: SCOPE, query: 'PRIVATE_TEST_MEMORY_FACT' },
  })));
  for (const answer of answers) {
    assert.notEqual(answer.isError, true);
    const graph = JSON.parse(answer.content.find((item) => item.type === 'text').text);
    assert.deepEqual(graph.entities[0].observations, ['PRIVATE_TEST_MEMORY_FACT']);
  }
  const mcpWrite = await clients[1].rpc('tools/call', {
    name: 'remember', arguments: rememberArguments({ name: 'MCP writer', text: 'Curated over stdio.' }),
  });
  assert.notEqual(mcpWrite.isError, true);
  const localRead = await call(owner.socket, 'open_nodes', { scope: SCOPE, names: ['MCP writer'] });
  assert.equal(localRead.body.entities[0].name, 'MCP writer');
  const status = await unixRequest(owner.socket, 'GET', '/v1/status');
  assert.equal(status.body.pendingCount, 4);
  assert.doesNotMatch(status.raw, /PRIVATE_TEST_MEMORY_FACT/);
});

test('a simultaneous owner is refused by kernel flock with exit 75 and cannot disrupt the live daemon', { timeout: 60_000 }, async (t) => {
  const owner = await daemon(t);
  await call(owner.socket, 'remember', rememberArguments());
  const duplicate = spawnCli(t, [
    'daemon', '--state-dir', owner.stateDir,
    '--socket', path.join(owner.directory, 'duplicate.sock'),
    '--account-id', ACCOUNT, '--actor-id', ACTOR_A,
  ]);

  const result = await exited(duplicate);

  assert.equal(result.code, 75, duplicate.stderr);
  const status = await unixRequest(owner.socket, 'GET', '/v1/status');
  assert.equal(status.status, 200);
  assert.equal(status.body.pendingCount, 2);
  const graph = await call(owner.socket, 'read_graph', { scope: SCOPE });
  assert.equal(graph.body.entities[0].name, 'Kebun');
});

test('a crash after a local response preserves committed events/outbox and releases the kernel lock for restart', { timeout: 90_000 }, async (t) => {
  const first = await daemon(t);
  assert.equal((await call(first.socket, 'remember', rememberArguments({ text: 'Committed before SIGKILL.' }))).status, 200);
  await stopChild(first.child, { processGroup: true, signal: 'SIGKILL' });
  // The fixture owns this runtime directory; no live or foreign socket is removed.
  await rm(first.socket, { force: true });
  const restarted = await daemon(t, { directory: first.directory, stateDir: first.stateDir, socket: first.socket });

  const status = await unixRequest(restarted.socket, 'GET', '/v1/status');
  assert.equal(status.body.pendingCount, 2);
  assert.equal(status.body.cursor, null);
  const graph = await call(restarted.socket, 'read_graph', { scope: SCOPE });
  assert.deepEqual(graph.body.entities[0].observations, ['Committed before SIGKILL.']);
});

test('local transport rejects malformed/unknown arguments without mutating state or leaking submitted memory text', { timeout: 60_000 }, async (t) => {
  const owner = await daemon(t);
  const marker = 'PRIVATE_TEST_INVALID_MEMORY_SENTINEL';
  const invalid = await call(owner.socket, 'remember', {
    ...rememberArguments({ text: marker }), unexpected: marker,
  });
  assert.equal(invalid.status, 400);
  assert.doesNotMatch(invalid.raw, new RegExp(marker));
  const malformed = await unixRequest(owner.socket, 'POST', '/v1/call', '{not-json');
  assert.equal(malformed.status, 400);
  assert.equal((await call(owner.socket, 'read_graph', { scope: SCOPE })).body.entities.length, 0);
  assert.equal((await unixRequest(owner.socket, 'GET', '/v1/status')).body.pendingCount, 0);
  const unknownField = await unixRequest(owner.socket, 'POST', '/v1/call', { tool: 'read_graph', arguments: { scope: SCOPE }, extra: true });
  assert.equal(unknownField.status, 400);
});

test('CLI export exclusively creates a 0600 backup; import unions and restore refuses initialized state', { timeout: 120_000 }, async (t) => {
  const owner = await daemon(t);
  await call(owner.socket, 'remember', rememberArguments({ text: 'Exported fact.' }));
  const backupPath = path.join(owner.directory, 'backup.json');
  await run(process.execPath, [cliPath, 'export', '--socket', owner.socket, '--output', backupPath]);
  assert.equal((await stat(backupPath)).mode & 0o777, 0o600);
  const originalBytes = await readFile(backupPath, 'utf8');
  const backup = JSON.parse(originalBytes);
  assert.equal(backup.formatVersion, 1);
  assert.equal(backup.events.length, 2);
  await assert.rejects(run(process.execPath, [cliPath, 'export', '--socket', owner.socket, '--output', backupPath]));
  assert.equal(await readFile(backupPath, 'utf8'), originalBytes);

  const guard = path.join(owner.directory, 'guard');
  const link = path.join(owner.directory, 'backup-link.json');
  await writeFile(guard, 'do not overwrite', { mode: 0o600 });
  await symlink(guard, link);
  await assert.rejects(run(process.execPath, [cliPath, 'export', '--socket', owner.socket, '--output', link]));
  assert.equal(await readFile(guard, 'utf8'), 'do not overwrite');

  await call(owner.socket, 'remember', rememberArguments({ name: 'New local entity', text: 'Must survive import.' }));
  await run(process.execPath, [cliPath, 'import', '--socket', owner.socket, '--input', backupPath]);
  const graph = await call(owner.socket, 'read_graph', { scope: SCOPE });
  assert.deepEqual(graph.body.entities.map((item) => item.name), ['Kebun', 'New local entity']);
  const cliStatus = await run(process.execPath, [cliPath, 'status', '--socket', owner.socket]);
  assert.equal(JSON.parse(cliStatus.stdout).pendingCount, 4);

  await stopChild(owner.child, { processGroup: true });
  const initializedRestore = spawnCli(t, [
    'daemon', '--state-dir', owner.stateDir, '--socket', path.join(owner.directory, 'refused-restore.sock'),
    '--account-id', ACCOUNT, '--actor-id', ACTOR_A, '--restore', backupPath,
  ]);
  assert.notEqual((await exited(initializedRestore)).code, 0);
  const restored = await daemon(t, { extraArgs: ['--restore', backupPath] });
  const restoredStatus = await unixRequest(restored.socket, 'GET', '/v1/status');
  assert.equal(restoredStatus.body.pendingCount, 2);
  assert.equal(restoredStatus.body.cursor, null);
  assert.deepEqual((await call(restored.socket, 'read_graph', { scope: SCOPE })).body.entities[0].observations, ['Exported fact.']);
});

test('daemon refuses occupied socket paths, relative paths, and symlink state directories without clobbering them', { timeout: 60_000 }, async (t) => {
  const directory = await temporaryDirectory(t, 'unsafe-paths');
  const occupied = path.join(directory, 'occupied.sock');
  await writeFile(occupied, 'foreign path sentinel', { mode: 0o600 });
  const realState = path.join(directory, 'real-state');
  await mkdir(realState, { mode: 0o700 });
  const linkedState = path.join(directory, 'linked-state');
  await symlink(realState, linkedState);
  const attempts = [
    ['--state-dir', path.join(directory, 'occupied-state'), '--socket', occupied],
    ['--state-dir', linkedState, '--socket', path.join(directory, 'symlink.sock')],
    ['--state-dir', 'relative-state', '--socket', path.join(directory, 'relative.sock')],
  ];
  for (const args of attempts) {
    const candidate = spawnCli(t, ['daemon', ...args, '--account-id', ACCOUNT, '--actor-id', ACTOR_A], { cwd: directory });
    assert.notEqual((await exited(candidate)).code, 0, candidate.stderr);
  }
  assert.equal(await readFile(occupied, 'utf8'), 'foreign path sentinel');
});
