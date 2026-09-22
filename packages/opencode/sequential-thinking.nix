# Backport 2026.8.31: restores nextThoughtNeeded to the tool schema's required
# fields and reports the package version instead of the stale 0.2.0 literal.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  typescript,
}:
buildNpmPackage (finalAttrs: {
  pname = "mcp-server-sequential-thinking";
  version = "2026.8.31";

  src = fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "servers";
    tag = finalAttrs.version;
    hash = "sha256-6woyDFfHbv8oZDN7lXrNnjZM8viYsBfMe/NtcHdDZcw=";
  };

  nativeBuildInputs = [typescript];

  dontNpmPrune = true;
  npmWorkspace = "src/sequentialthinking";
  npmDepsHash = "sha256-psy1XH4DuZu2+tkHpe/bQw3R7uNr8nF5u/AFKoxJeTg=";

  # Match nixpkgs' package cleanup: only the selected workspace's executable
  # is needed, and retaining sibling servers causes profile collisions.
  postInstall = ''
    rm -rf $out/lib/node_modules/@modelcontextprotocol/servers/node_modules/@modelcontextprotocol/server-filesystem
    rm -rf $out/lib/node_modules/@modelcontextprotocol/servers/node_modules/@modelcontextprotocol/server-memory
    rm -rf $out/lib/node_modules/@modelcontextprotocol/servers/node_modules/@modelcontextprotocol/server-everything
    rm -rf $out/lib/node_modules/@modelcontextprotocol/servers/node_modules/@modelcontextprotocol/server-sequential-thinking
    rm -rf $out/lib/node_modules/@modelcontextprotocol/servers/node_modules/.bin
  '';

  meta = {
    changelog = "https://github.com/modelcontextprotocol/servers/releases/tag/${finalAttrs.version}";
    description = "MCP server for sequential thinking and problem solving";
    homepage = "https://github.com/modelcontextprotocol/servers";
    license = lib.licenses.mit;
    mainProgram = "mcp-server-sequential-thinking";
    platforms = lib.platforms.all;
  };
})
