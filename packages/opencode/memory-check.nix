# Exercise the installed artifact, including PGlite's non-JavaScript assets.
# PostgreSQL fixtures are private, temporary clusters; no host database is used.
{
  runCommand,
  nodejs_24,
  postgresql_16,
  util-linux,
  memory,
}:
runCommand "kebun-memory-checks" {
  nativeBuildInputs = [nodejs_24 postgresql_16 util-linux];
} ''
  cp -R ${memory}/lib/kebun-memory app
  chmod -R u+w app
  cp -R ${./memory/tests} app/tests
  export MEMORY_TEST_TMPDIR="$TMPDIR"
  export MEMORY_TEST_POSTGRES_BIN=${postgresql_16}/bin
  export KEBUN_MEMORY_FLOCK=${util-linux}/bin/flock
  cd app
  node --test --test-concurrency=1 tests/*.test.js
  touch "$out"
''
