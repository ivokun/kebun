# BrowserMCP 0.1.3 — the stdio MCP server for the Browser MCP browser
# extension. Packed from the npm registry tarball (upstream's repo has no
# self-contained source tree for this version); the committed lockfile pins
# the resolved dependency tree, and npmDepsHash pins its contents.
{
  buildNpmPackage,
  coreutils,
  fetchzip,
  findutils,
  lib,
  lsof,
  makeWrapper,
  nodejs,
}:
buildNpmPackage {
  pname = "mcp-server-browsermcp";
  version = "0.1.3";

  src = fetchzip {
    url = "https://registry.npmjs.org/@browsermcp/mcp/-/mcp-0.1.3.tgz";
    hash = "sha256-NHFknZ2a7dKKcmLikFD6J1cjG/D4a1LBNr9xCYRpFF8=";
  };

  # The npm tarball ships no lockfile; ours pins the resolved tree. The
  # tarball's devDependencies use pnpm-style "workspace:*" specs from
  # upstream's monorepo which npm ci cannot resolve and which are absent
  # from the published dependency tree, so drop them.
  postPatch = ''
        cp ${./browsermcp-package-lock.json} package-lock.json
        # GNU xargs otherwise invokes `kill -9` once with no PID whenever the
        # port is already free, producing a spurious startup error.
        substituteInPlace dist/index.js \
          --replace-fail 'lsof -ti:''${port} | xargs kill -9' \
          'lsof -ti:''${port} | xargs -r kill -9'
      ${nodejs}/bin/node -e '
        const fs = require("fs");
        const p = JSON.parse(fs.readFileSync("package.json"));
        delete p.devDependencies;
        delete p.overrides;
        fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");

        // Upstream replaces server.close and then recursively calls that same
        // replacement. Preserve the original method before wrapping it so
        // normal MCP EOF/shutdown does not overflow the stack.
        const distFile = "dist/index.js";
        const dist = fs.readFileSync(distFile, "utf8");
        const closeBefore = "  server.close = async () => {\n    await server.close();";
        const closeAfter = "  const closeServer = server.close.bind(server);\n  server.close = async () => {\n    await closeServer();";
        if (!dist.includes(closeBefore)) throw new Error("BrowserMCP close wrapper changed upstream");

        // The published server listens on every interface and accepts WebSocket
        // upgrades from any website. Limit it to loopback and to the official
        // BrowserMCP Chrome extension. rawHeaders makes duplicate Origin
        // headers fail closed instead of using the Node-normalized value alone.
        const websocketBefore = "  return new WebSocketServer({ port });";
        const websocketAfter = `  return new WebSocketServer({
      port,
      host: "127.0.0.1",
      verifyClient: ({ origin, req }, done) => {
        const origins = [];
        for (let index = 0; index < req.rawHeaders.length; index += 2) {
          if (req.rawHeaders[index].toLowerCase() === "origin") {
            origins.push(req.rawHeaders[index + 1]);
          }
        }
        const allowedOrigin = "chrome-extension://bjfgambnhccakkhmkepdoekmckoijdlc";
        if (origins.length === 1 && origins[0] === allowedOrigin && origin === allowedOrigin) {
          done(true);
          return;
        }
        done(false, 403, "Forbidden");
      }
    });`;
        if (!dist.includes(websocketBefore)) throw new Error("BrowserMCP WebSocket listener changed upstream");

        fs.writeFileSync(
          distFile,
          dist.replace(closeBefore, closeAfter).replace(websocketBefore, websocketAfter),
        );
      '
  '';

  npmDepsHash = "sha256-10KZi5FsgsgNvVvvvG44ucBr144UkGZt8BaC8RmZpPo=";

  # dist/ ships prebuilt in the tarball.
  dontNpmBuild = true;

  # npm pack (used by the install hook to enumerate package files) runs
  # the "prepare" script by default; keep it inert like npm ci above.
  npmPackFlags = ["--ignore-scripts"];

  # BrowserMCP clears a stale listener on its extension port with
  # `lsof -ti:9009 | xargs kill -9`. Supply that runtime PATH explicitly
  # instead of relying on whichever commands happen to be in the session.
  nativeBuildInputs = [makeWrapper];
  postFixup = ''
    wrapProgram "$out/bin/mcp-server-browsermcp" \
      --prefix PATH : ${lib.makeBinPath [lsof findutils coreutils]}
  '';

  meta.mainProgram = "mcp-server-browsermcp";
}
