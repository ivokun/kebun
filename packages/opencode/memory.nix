# One immutable artifact for the local owner, stdio adapters and sync server.
# No npm command is run at launch; PGlite resolves its WASM/data assets from
# the complete dependency tree retained beside the compiled ESM application.
{
  lib,
  buildNpmPackage,
  cacert,
  makeWrapper,
  nodejs_24,
  util-linux,
}:
buildNpmPackage {
  pname = "kebun-memory";
  version = "0.1.0";
  nodejs = nodejs_24;

  src = lib.fileset.toSource {
    root = ./memory;
    fileset = lib.fileset.unions [
      ./memory/src
      ./memory/package.json
      ./memory/package-lock.json
      ./memory/tsconfig.json
    ];
  };

  # prefetch-npm-deps packages/opencode/memory/package-lock.json
  npmDepsHash = "sha256-1EEx1g5cnd+0auFwCbS+T0yUEFCjVqcaXqt/O27j5Y4=";
  nativeBuildInputs = [makeWrapper];
  npmFlags = ["--ignore-scripts"];
  npmRebuildFlags = ["--ignore-scripts"];
  env = {
    npm_config_audit = "false";
    npm_config_fund = "false";
    npm_config_offline = "true";
  };

  # Compile with the pinned TypeScript dev dependency, then remove dev-only
  # dependencies without running lifecycle scripts or using the network.
  # Copy whole runtime dependencies, not a JS-only bundle: PGlite also needs
  # pglite.data, pglite.wasm, initdb.wasm and its relative worker/chunk files.
  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --ignore-scripts --offline
    app="$out/lib/kebun-memory"
    mkdir -p "$app" "$out/bin"
    cp package.json "$app/"
    cp -r dist node_modules "$app/"
    test -s "$app/dist/cli.js"
    test -s "$app/node_modules/@electric-sql/pglite/dist/pglite.wasm"
    test -s "$app/node_modules/@electric-sql/pglite/dist/pglite.data"
    test -s "$app/node_modules/@electric-sql/pglite/dist/initdb.wasm"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/kebun-memory" \
      --add-flags "$app/dist/cli.js" \
      --set KEBUN_MEMORY_FLOCK ${util-linux}/bin/flock \
      --set-default NODE_EXTRA_CA_CERTS ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --unset NODE_OPTIONS \
      --unset NODE_PATH

    runHook postInstall
  '';

  meta = {
    description = "Local-first scoped memory daemon, MCP adapter and authenticated sync server";
    mainProgram = "kebun-memory";
    platforms = lib.platforms.linux;
  };
}
