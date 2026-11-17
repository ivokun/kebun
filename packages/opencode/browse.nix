# OpenCode Browse: one native binary that is the CLI, the localhost relay
# (127.0.0.1:19988) and the stdio MCP server (`browse mcp`) the Chromium
# extension pairs with. Built from the tagged source rather than the release
# service's tarball so no self-replacing binary lands in ~/.local/bin.
#
# A Nix-store executable is detected as an "other" install (method.rs:
# not ~/.local/bin, not an npm package, not a cargo target dir), which never
# updates itself; the MCP launcher additionally sets
# OPENCODE_BROWSER_AUTO_UPDATE=off. Bump by changing version + hashes here.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "browse";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "browse";
    tag = "v${finalAttrs.version}";
    hash = "sha256-5AKN01QsquK7XmaGSo7eiFbUcus2Q+teO+++7qReUbw=";
  };

  sourceRoot = "${finalAttrs.src.name}/rust";
  cargoHash = "sha256-RC27sSYrjnCFN6CpNnO0QPRxTleBPrGQRWEwg4USLVI=";

  cargoBuildFlags = ["-p" "browse"];
  # The test suites drive a relay over loopback sockets and temp HOMEs; the
  # sandbox build only needs the binary.
  doCheck = false;

  env.BROWSE_VERSION = finalAttrs.version;

  meta = {
    description = "Let AI agents drive your real Chromium browser over MCP";
    homepage = "https://github.com/anomalyco/browse";
    license = lib.licenses.mit;
    mainProgram = "browse";
    platforms = lib.platforms.linux;
  };
})
