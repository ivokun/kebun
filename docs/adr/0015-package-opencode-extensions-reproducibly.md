# ADR-0015: Package OpenCode extensions reproducibly and reduce credential exposure

- Status: Accepted
- Date: 2026-09-21
- Deciders: Ivokun
- Tags: opencode, mcp, nix, supply-chain, secrets

## Context

`home/opencode/opencode.json` wires seven local MCP servers plus plugins.
Before this change, the non-nixpkgs entries were effectively
unreproducible at the point of use: an `npx <package>`-style launch resolved
the dependency tree from the npm registry at every OpenCode startup, with no
lockfile pinning and no hash over what was fetched. A published tarball (or
any transitive dependency of one) could change between launches without a
rebuild or a repo change.

The credential side had the mirror-image problem. The official
`github-mcp-server` needs a GitHub token, while token variables exported by
the shell were inherited by OpenCode, every plugin, and every MCP child.
Only the GitHub server needs a token in its environment. The token that `gh`
stores in the desktop keyring is a separate trust boundary: any process
running as `ivokun` can ask the unlocked keyring for it, so process
environment cleanup cannot provide same-user credential isolation.

Two deployment facts frame the decision: the packaging was implemented and
sanity-evaluated on the reference machine, but the runtime target is sakura.
This decision is accepted; deployment and runtime validation on sakura are
still pending. ADR-0016 subsequently moved the managed binary and plugins to
OpenCode V2 while preserving the supply-chain and credential boundaries below;
both decisions share the same pending sakura runtime gate.

## Decision

### Reproducibility: every local MCP server runs from a Nix-store executable

`packages/opencode/default.nix` is a plain attrset consumed with
`import ../../packages/opencode {inherit pkgs;}` and added to
`home.packages` in `home/features/opencode.nix`. That module parses the
readable source `opencode.json` and renders every local MCP command with
absolute store paths, so PATH cannot substitute another executable. Nothing
under `mcp` downloads anything at launch. Four sourcing choices are kept
deliberately distinct:

The same package set provides a managed `opencode` wrapper. It executes the
exact `pkgs.opencode` store path (now V2 2.0.12, packaged in-tree by
ADR-0016), disables self-updates, strips ambient GitHub credentials before
plugins or tools load, and is prepended to the Home Manager session PATH so an
unmanaged `~/.opencode/bin` or mise install cannot shadow it.
`lib/opencode-overlay.nix` applies the package replacement to both the host and
nested Home Manager package sets; without the second application, Home Manager
silently falls back to the channel's V1 package.

1. **Pinned nixpkgs packages.** `mcp-server-memory` and `mcp-nixos` come
   from the flake's pinned nixpkgs input. Their current versions remain
   suitable for local stdio use; `mcp-nixos` must be revisited before any
   HTTP transport is enabled. Version drift is bounded by the nixpkgs input
   pin and moves only with an intentional flake update.

2. **Security and compatibility backports.** Two packages cannot wait for
   the pinned nixpkgs revision:
   - `mcp-server-sequential-thinking` 2026.8.31 restores
     `nextThoughtNeeded` to the tool schema's required fields and reports its
     real package version.
   - `github-mcp-server` 1.12.2 includes the authority, URL, response, write,
     and schema hardening released after the channel's 1.6.0 package. This is
     particularly relevant because the process receives a live GitHub token.

   `packages/opencode/{sequential-thinking,github-mcp-server}.nix` pin the
   official release tags, source hashes, and npm/Go dependency hashes.
   Because
   `mcp-server-memory` and `mcp-server-sequential-thinking` each install
   the full `@modelcontextprotocol/servers` mono-repo tree and collide when
   both land in one `home.packages` buildEnv, only their bin wrappers need
   to be on PATH — `mcp-servers` is a link farm of the four executables
   rather than four full packages.

3. **npm-registry tarballs with committed lockfiles.** `browsermcp` (0.1.3)
   and `gitnexus` (1.6.12) have no usable nixpkgs expression, so each is a
   `buildNpmPackage` in `packages/opencode/*.nix` that fetches the exact
   registry tarball by SRI hash. The tarballs ship no lockfile, so committed
   `packages/opencode/*-package-lock.json` files pin their resolved dependency
   trees and `npmDepsHash` pins the contents. Dev dependencies and root-only
   overrides are stripped because the published trees cannot resolve their
   pnpm `workspace:*` specifications. Install scripts remain inert, with the
   one native-module copy `@ladybugdb/core` needs done explicitly in
   `postInstall`. BrowserMCP's wrapper supplies `lsof`, `xargs`, and `kill`;
   three narrow downstream patches make empty `xargs` input a no-op, preserve
   the original MCP `close` method, and bind the WebSocket bridge to IPv4
   loopback while accepting upgrades only from the official BrowserMCP Chrome
   extension origin.

4. **Pinned push-plugin tarball without a runtime dependency install.**
   `@whisperopencode/push` 0.3.0 is fetched by SRI hash. ADR-0016 replaces its
   V1-only entrypoint with a reviewed V2 event adapter before esbuild bundles
   the published relative modules. That entrypoint needs only relative modules
   and Node built-ins, so it has no npm dependency closure or committed lockfile
   and performs no registry access at startup.

The excalidraw MCP server is the prebuilt repo bundle, kept in the store by
a trivial `runCommand`; nothing is deployed under `~/.config/opencode/mcp/`
any more.

### Plugins: local files, zero npm-registry fetches at startup

OpenCode auto-loads plugins from `~/.config/opencode/plugins/`. Both
plugins are deployed as single local files there:
`env-protection.js` is a repo file (blocks `read` on `.env` files), and
`whisperopencode-push.js` is the Nix-built plugin — the registry tarball's
dist entry bundles (esbuild, from the Nix-store esbuild) into one
self-contained ESM file staged via `xdg.configFile` from the stable store
path. The dotenv hook is defense against accidental `read` calls, not a
sandbox against shell or same-uid file access. No plugin is fetched from the
npm registry at startup.

### Credential handling: `gh auth token` + `env -i`, ambient tokens stripped elsewhere

- **GitHub token acquisition.** `opencode-github-mcp` (a
  `writeShellScriptBin` in `packages/opencode/default.nix`) fetches the
  token per launch from the `gh` keyring (`gh auth token --hostname
  github.com`) after unsetting token environment overrides — no token is
  stored in the repo, the Nix store, or any config file — and execs
  `github-mcp-server stdio` under `env -i` with only `HOME`, the pinned CA
  bundle, and `GITHUB_PERSONAL_ACCESS_TOKEN` set. The wrapper explicitly
  injects the token into only that child environment for the lifetime of the
  server. The server runs in `--lockdown-mode` and `--read-only`, with only
  the `repos`, `issues`, `pull_requests`, and `users` toolsets enabled.
  GitHub writes remain an explicit operator action through `gh`, not an MCP
  capability exposed to prompt-driven content.
- **Ambient stripping.** Home Manager renders every other local MCP command
  with an absolute `env -u` prefix that strips `GITHUB_TOKEN`, `GH_TOKEN`,
  `GITHUB_PERSONAL_ACCESS_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, and
  `GH_ENTERPRISE_TOKEN`; the Excalidraw wrapper does the same. The nixos MCP
  additionally strips `PYTHONPATH` to keep the pinned interpreter
  environment clean.
- **Parent cleanup.** The managed OpenCode wrapper removes those same
  variables before OpenCode loads plugins or exposes shell tools. Per-MCP
  stripping remains as defense in depth if a server wrapper is invoked
  directly.
- **Trust-boundary limit.** These measures prevent accidental inheritance
  and reduce passive disclosure; they are not a sandbox. OpenCode, plugins,
  MCP servers, and shell tools all run as `ivokun`, so any of them can invoke
  `gh auth token` or access the unlocked Secret Service keyring. Sakura's
  `gh` login must therefore use a dedicated, least-privilege GitHub token,
  restricted to the repositories it must inspect and read-only metadata,
  contents, issue, and pull-request permissions. Strong isolation would
  require a separate Unix identity or a capability broker and is outside
  this decision.

## Consequences

### Positive

- Every local MCP executable and plugin artifact is pinned and store-managed;
  changed fixed-output sources or dependency trees fail their declared hashes
  instead of silently replacing the reviewed inputs. The remote Obsidian MCP
  remains a network service and is outside this supply-chain guarantee.
- No network access is required to start OpenCode's local MCP servers;
  first `nixos-rebuild` after a version bump is the only fetch point.
- Only `github-mcp-server` receives a token through process-environment
  inheritance. Ambient GitHub token variables do not reach OpenCode plugins,
  tools, or non-GitHub MCP children.
- GitHub MCP cannot mutate repositories, issues, or pull requests, and does
  not register unrelated actions, organization, notification, secret, or
  security toolsets. Lockdown mode filters untrusted public-repository
  content as a best-effort prompt-injection reduction.
- Lockfile and hash updates are reviewable diffs in git; the resolved tree
  npm ci installs is exactly the tree the original npx run used.

### Negative

- **Version pinning is manual.** Bumping browsermcp or gitnexus means a new
  tarball URL and hash, regenerated committed lockfile, and recomputed
  `npmDepsHash`. Bumping whisperopencode-push requires a new tarball hash and
  re-review of whether the local V2 adapter is still needed and compatible.
- MCP packages are pinned through three mechanisms — nixpkgs, explicit
  release backports, and registry tarballs — and drift independently. Version
  review must cover all three rather than assuming a flake update moves the
  whole set together.
- BrowserMCP carries three guarded patches against its published bundle. A
  version bump must revalidate them; the build fails if any source pattern
  changes rather than silently omitting the fix.
- `env -i` in `opencode-github-mcp` is unforgiving: the child gets no
  locale, proxy, or CA environment. If github-mcp-server ever needs one
  (e.g. behind a corporate proxy), the wrapper must be extended
  deliberately.
- The `env -u` list is by-name and incomplete by nature: it covers the
  known GitHub/gh token variable spellings, not arbitrary ambient secrets.
- `gh auth token` couples the MCP server's health to the `gh` keyring
  state; if `gh` is logged out, the github MCP fails to start (by design —
  it exits rather than starting tokenless).
- Same-user code can independently retrieve the keyring-backed token. The
  least-privilege GitHub token is therefore the security boundary; `env -i`
  is environment hygiene, not credential isolation.
- The BrowserMCP bridge accepts only the official Chrome extension
  (`chrome-extension://bjfgambnhccakkhmkepdoekmckoijdlc`). Unofficial builds
  and hypothetical Firefox ports are rejected until their origins are
  deliberately reviewed and allowlisted.

### Neutral

- The mcp-servers link farm is a workaround for a nixpkgs mono-repo
  packaging collision, invisible to `opencode.json`.
- The lockfiles are generated from the dependency perspective (devDeps
  dropped), not upstream's monorepo perspective — regenerating them
  requires reproducing that perspective, not copying upstream's lockfile.
- At the time of this decision, OpenCode's binary was the overlay-pinned
  1.18.11 package and this ADR added only the managed wrapper. ADR-0016 now
  packages V2 2.0.12 in `packages/opencode/opencode-v2.nix`; the wrapper and
  extension trust boundaries remain the ones defined here.

## References

- `packages/opencode/default.nix` — packaging entrypoint, mcp-servers link farm, `opencode-github-mcp` wrapper
- `packages/opencode/{sequential-thinking,github-mcp-server}.nix` — release-tag backports with fixed dependency hashes
- `lib/opencode-overlay.nix` — shared package replacement for host and Home Manager package sets
- `packages/opencode/opencode-v2.nix` — OpenCode V2 package added by ADR-0016
- `packages/opencode/{browsermcp,gitnexus}.nix` + committed `*-package-lock.json` — tarball+lockfile builds
- `packages/opencode/{whisperopencode-push.nix,whisperopencode-push-v2.js}` — pinned push-plugin tarball and V2 adapter
- `home/features/opencode.nix` — deployment, absolute MCP command rendering, and `home.packages`
- `home/opencode/opencode.json` — readable source configuration rendered by Home Manager
- `home/opencode/plugins/env-protection.js` — local plugin example
- [Official BrowserMCP Chrome extension](https://chromewebstore.google.com/detail/browser-mcp-automate-your/bjfgambnhccakkhmkepdoekmckoijdlc) — fixed origin allowlisted by the loopback WebSocket bridge
- [BrowserMCP 0.1.3 WebSocket source](https://github.com/BrowserMCP/mcp/blob/9db12f2b4f61294f0bc11708986abc47db539d6c/src/ws.ts) — upstream listener patched at build time
- ADR-0014 — workstation trust-boundary hardening (this ADR covers the OpenCode supply-chain and credential-environment slice it deliberately deferred)
- ADR-0016 — managed OpenCode V2 package, config, and plugin migration

## Notes

- 2026-09-22: ADR-0016 moved the managed binary and local plugin APIs to V2
  2.0.12. The MCP packaging, wrapper hardening, and credential boundaries in
  this ADR carry over unchanged.
- Date proposed: 2026-09-21
- Date accepted: 2026-09-21
- Proposed by: Ivokun
- Accepted by: Ivokun
