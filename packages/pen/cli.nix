# pen.dev CLI 0.3.14 (formerly Pencil CLI) — headless .pen editing, the
# `pen interactive` MCP shell, and `pen --agent …` prompt runs. Packed from
# the npm registry tarball; the committed lockfile (cli-package-lock.json)
# pins the resolved dependency tree, and npmDepsHash pins its contents.
#
# Not needed for MCP: the desktop app (./default.nix) bundles its own MCP
# server, which the agents reach via opencode-pencil-mcp. The CLI bundles
# the same Go server under dist/out for its own use.
#
# dist/ ships prebuilt (tsdown bundle + wasm + the per-platform Go MCP
# servers), so there is no build step. Native pieces — sharp's libvips, the
# Claude Agent SDK and Codex binaries, the Go MCP server — are upstream
# prebuilds; npm installs the linux/x64 optional variants (its --libc
# filter does not exclude the musl ones, so postInstall deletes those) and
# autoPatchelf points them at store libraries instead of /lib64.
#
# Updates: regenerate the lockfile from the new tarball's package.json with
# devDependencies and scripts removed —
#   npm install --package-lock-only --ignore-scripts
# then bump version + src hash, and refresh npmDepsHash (set it to
# lib.fakeHash and copy the expected value from the build error).
{
  lib,
  stdenv,
  buildNpmPackage,
  fetchzip,
  nodejs_22,
  autoPatchelfHook,
  libxcb,
}:
buildNpmPackage rec {
  pname = "pen-cli";
  version = "0.3.14";

  src = fetchzip {
    url = "https://registry.npmjs.org/@pen.dev/cli/-/cli-${version}.tgz";
    hash = "sha256-szEHjZTpCAVyPB/wSLErurumpM4QRvVSo1prhxpOLIc=";
  };

  # engines.node >= 22.19.
  nodejs = nodejs_22;

  # The tarball ships no lockfile, and its devDependencies are unpublished
  # workspace packages (@ha/*) — drop them so npm resolves only the runtime
  # tree, matching how `npm install -g` sees it.
  postPatch = ''
    cp ${./cli-package-lock.json} package-lock.json
    ${nodejs_22}/bin/node -e '
      const fs = require("fs");
      const p = JSON.parse(fs.readFileSync("package.json"));
      delete p.devDependencies;
      delete p.scripts;
      fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
    '
  '';

  npmDepsHash = "sha256-peTVm45yaNARUc2DrYlszFLdNsv0nA44ErMj5+Ijn6Q=";

  dontNpmBuild = true;

  # Only this platform's optional native variants; no install scripts run
  # (every native module here ships its binary in the tarball).
  npmFlags = ["--ignore-scripts" "--os=linux" "--cpu=x64"];
  npmPackFlags = ["--ignore-scripts"];
  npmRebuildFlags = ["--ignore-scripts"];

  nativeBuildInputs = [autoPatchelfHook];
  # libxcb: pi-tui's X11 clipboard addon.
  buildInputs = [stdenv.cc.cc.lib libxcb];

  # Drop other platforms' MCP servers and the musl native variants so
  # autoPatchelf sees only linux-x64 glibc ELF files.
  postInstall = ''
    root=$out/lib/node_modules/@pen.dev/cli
    find "$root/dist/out" -maxdepth 1 -name 'mcp-server-*' ! -name 'mcp-server-linux-x64' -delete
    test -x "$root/dist/out/mcp-server-linux-x64"
    rm -rf "$root"/node_modules/@img/sharp-*linuxmusl-* \
      "$root"/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64-musl
  '';

  meta = {
    description = "pen.dev command-line interface for .pen design files";
    homepage = "https://docs.pen.dev/for-developers/pen-cli";
    license = lib.licenses.unfree;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode lib.sourceTypes.binaryBytecode];
    platforms = ["x86_64-linux"];
    mainProgram = "pen";
  };
}
