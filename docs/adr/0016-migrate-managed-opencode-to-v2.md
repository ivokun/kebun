# ADR-0016: Migrate the managed OpenCode installation to V2

- Status: Accepted (build verified; activation on sakura pending)
- Date: 2026-09-22
- Deciders: Ivokun
- Tags: opencode, v2, nix, plugins, mcp

## Context

ADR-0015 made OpenCode's MCP servers, local plugins, and credential handling
reproducible, but the managed binary and configuration still targeted OpenCode
1.18.11 and its V1 plugin API. A move to V2 is not a source-hash-only update:
V2 changes the server and plugin APIs, introduces a native configuration shape,
and no longer provides LSP tools even though it accepts legacy LSP settings.

The pinned nixpkgs revision does not package the required V2 release. Installing
OpenCode through its own updater would bypass the repository's package pin,
wrapper hardening, and build-only deployment gate.

## Decision

### Package OpenCode V2 in the repository

`packages/opencode/opencode-v2.nix` initially built the `v2.0.12` source tag
and now builds `v2.0.18`. It follows upstream's Nix packaging approach:

- source and the Bun dependency closure are fixed-output, hash-pinned inputs;
- `bun install --frozen-lockfile --ignore-scripts` runs only during the Nix
  build, never at OpenCode startup;
- the bundled models.dev snapshot prevents runtime model-catalog downloads;
- the package disables automatic updates and supplies its runtime `ripgrep`
  and Wayland dependencies explicitly.

The 2.0.18 dependency closure hash was recomputed with the pinned Nix/Bun
toolchain. The hash published in upstream's `nix/hashes.json` did not reproduce
with upstream's own locked flake, while both that clean flake and kebun produced
the same replacement hash.

Bun's single-file build does not retain the optional native
`@parcel/watcher-linux-x64-glibc` addon. Without it, OpenCode starts but logs
`watcher backend not supported` and silently loses recursive directory watches.
The package therefore copies the hash-pinned `watcher.node` into its output,
sets upstream's `OPENCODE_PARCEL_WATCHER_PATH` escape hatch, and supplies the
addon's C++ runtime in the package-local wrapper environment. The build fails
if the expected addon disappears on a future source or lockfile update.

`lib/opencode-overlay.nix` replaces `pkgs.opencode` with this package in both
the NixOS and nested Home Manager package sets. The two applications are
intentional: Home Manager otherwise evaluates a separate package set and can
silently retain nixpkgs' V1 package.

### Use the native V2 configuration and plugin APIs

`home/opencode/opencode.json` now uses:

- `agents` with model options under `request.body`;
- ordered `permissions` entries with `action`, `resource`, and `effect`;
- `mcp.servers`, with all seven local commands rendered to absolute store
  paths by `home/features/opencode.nix`;
- `update: "disable"`;
- an experimental hard policy that denies `read` requests for dotenv-like
  paths before saved approvals can allow them.

LSP, AST-grep, Context7, and legacy search permission actions and dependent
prompt instructions are removed. Repository-native grep/glob, GitNexus,
webfetch/websearch, build, type-check, and test commands replace those
assumptions.

Both local plugins use V2 definitions with stable IDs and `setup(ctx)`:

- `env-protection` registers `ctx.tool.hook("execute.before", ...)` as a
  defense-in-depth check alongside the hard policy;
- the pinned `@whisperopencode/push` 0.3.0 tarball receives a reviewed V2 event
  adapter at build time. The adapter subscribes through `ctx.event`, maps known
  V2 event shapes to their legacy equivalents, and passes unknown event types
  to the upstream recorder, whose existing filter decides what is retained.

Plugins are deployed under `~/.config/opencode/plugins/`. Neither plugin is
installed from npm at startup.

### Preserve the existing trust boundaries

The managed wrapper remains the user-facing `opencode` command. It:

- executes the exact store package and prevents an unmanaged installation from
  winning `PATH`;
- rejects `opencode update` and `opencode upgrade`;
- sets `OPENCODE_DISABLE_AUTOUPDATE=1`;
- removes ambient GitHub token variables before plugins and tools load.

ADR-0015's per-MCP sanitization, `env -i` GitHub wrapper, read-only/lockdown
flags, and requirement for a dedicated least-privilege `gh` credential remain
unchanged.

## Verification and rollout state

Build-only and isolated checks completed on ivokun-htpc without activating the
configuration:

- OpenCode builds as version 2.0.18, and the full sakura and ume system
  closures build;
- an isolated V2 service loads the rendered config with 17 custom agents and no
  normalization warnings;
- both local plugin IDs are discovered;
- the local Browser, Excalidraw, GitNexus, Memory, NixOS, and
  Sequential-Thinking MCP servers initialize from store paths; the GitHub MCP
  intentionally fails without a keyring credential and the remote Obsidian MCP
  correctly reports that authentication is required;
- BrowserMCP registers all 12 tools during the isolated smoke but later reports
  `Connection closed` in `mcp list`; stability with the real extension remains
  a post-activation check;
- the packaged native watcher starts directory subscriptions with the `inotify`
  backend and no `watcher backend not supported` error;
- the wrapper blocks self-updates, and all rendered local MCP commands avoid
  `npx`, `uvx`, and runtime package downloads.

The bundled, fetch-disabled models.dev snapshot contains
`kimi-for-coding/k3`; OpenCode Go supplies its account-backed catalog
dynamically, and the reference host lists `opencode-go/glm-5.3-flash` there.
The `opencode models` command lists only models whose providers are enabled,
so the isolated credential-free smoke exposes only OpenCode's public free
models. Seeing both selected IDs with sakura's real provider credentials
remains a deployment gate.

Activation and user-state checks must run on sakura only, after `nh os switch
.`: selected-model availability, provider credentials, GitHub keyring access,
the authenticated Obsidian MCP, real dotenv-hook behavior, push delivery, and
normal system/user service health. Until those pass, this ADR describes an
accepted and build-verified migration, not a completed deployment.

## Consequences

### Positive

- The binary, configuration, plugins, and local MCP servers now share one
  reproducible Nix-managed update path.
- V2 behavior is expressed in V2's native schema instead of relying on legacy
  normalization.
- The migration preserves update blocking, absolute executable paths, and
  credential-environment hygiene.
- The native inotify backend is packaged explicitly instead of failing
  silently.

### Negative

- OpenCode bumps now require source and dependency hash updates plus config,
  plugin, model, MCP, and watcher smoke tests.
- The local push adapter remains owned here until its upstream package ships a
  reviewed V2 entrypoint.
- The Bun dependency fixed-output derivation may need registry access on a cold
  build, although its result is content-addressed and hash checked.
- The pinned nixpkgs Bun may lag upstream's requested range, so the package
  turns that exact version gate into a warning. A version bump must prove the
  build and smoke checks with the pinned toolchain before hashes are accepted.
- The watcher addon's C++ library path is inherited by OpenCode child
  processes; this is scoped to the managed wrapper and is retained because it
  is the only verified way the compiled Bun runtime loads the addon.
- The migration preserves the existing broad shell/edit/subagent grants for
  implementation agents. Porting those rules to V2 is compatibility work, not
  a least-privilege redesign; tightening them needs a separate behavior review.

### Neutral

- The remote Obsidian MCP remains outside the local package reproducibility
  boundary.
- The push plugin is always discoverable but sends nothing unless its runtime
  state selects relay mode and supplies a relay. That endpoint and the
  completion metadata sent to it remain an operator-managed trust boundary.
- V2 still accepts legacy LSP configuration, but it does not run language
  servers or expose LSP tools; project commands are the supported replacement.

## References

- `packages/opencode/opencode-v2.nix` — V2 source, dependency closure, native watcher, and package wrapper
- `lib/opencode-overlay.nix` — shared NixOS/Home Manager package replacement
- `packages/opencode/default.nix` — managed command and MCP wrappers
- `packages/opencode/whisperopencode-push.nix` and `whisperopencode-push-v2.js` — pinned push plugin and V2 adapter
- `home/opencode/opencode.json` — native V2 source configuration
- `home/features/opencode.nix` — store-path rendering and Home Manager deployment
- [OpenCode V1-to-V2 migration guide](https://opencode.ai/v2/docs/migrate-v1)
- [OpenCode V2 plugin guide](https://opencode.ai/v2/docs/build/plugins)
- ADR-0005 — model-specific request options
- ADR-0015 — reproducible extensions and credential handling

## Notes

- 2026-09-28: bumped the in-tree package to 2.0.18, added the hard dotenv-read
  policy, and removed stale AST-grep/Context7 permission and prompt references.
- Date proposed: 2026-09-22
- Date accepted: 2026-09-22
- Proposed by: Ivokun
- Accepted by: Ivokun
