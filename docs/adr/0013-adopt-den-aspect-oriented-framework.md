# ADR-0013: Adopt Den (aspect-oriented Nix) as the configuration framework

- Status: Accepted
- Date: 2026-09-13
- Deciders: Ivokun
- Tags: nixos, den, architecture

## Context

Since ADR-0007 the Quattro migration made kebun's composition feature-first
(files per concern) but the wiring stayed host-first: `flake.nix` connected
everything through imperatively maintained lists (`sharedModules`,
`mkHomeManagerModules`) and conveyed `username`/`hostname`/`system` through
`specialArgs`/`extraSpecialArgs` for roughly two real consumers.

The aspect experiment (github:denful/den) inverts the matrix: one aspect per
concern, entities declared as data, context delivered as real function args
evaluated before the module fixpoint. Template semantics (batteries:
`define-user`, `primary-user`, `home-manager`, `hostname`) were validated
from den d50f0fce docs and source, and re-verified by a full topology eval.

## Decision

1. `flake.nix` becomes a Den entrypoint: `inputs.den.flakeModule` + a
   `modules/` directory evaluated with `nixpkgs.lib.evalModules`. All other
   inputs keep their pinned revisions.
2. `hosts/common/*.nix` move (byte-identical) to `modules/aspects/` and are
   included by aspects `core`, `desktop`, `dev`, `networking`, `printing`,
   `snapper` so the wiring is expressed as aspect `includes`.
3. Entities are declared as data: `den.hosts.x86_64-linux.sakura.users.ivokun`
   (`classes = ["homeManager"]`). The free-standing `programs.fish/zsh` and
   nix trusted-users settings from `hosts/common/users.nix` go into
   `den.aspects.shell-entry`; the per-user `users.users.ivokun` block goes
   into the ivokun user aspect via context args (`{ user, pkgs, ... }`).
4. Home Manager modules are imported untouched into
   `den.aspects.ivokun.homeManager`. Their `username`/`system`/`inputs` fn
   args are satisfied by `_module.args` at the class level — the
   module-system-level mechanism, which does not conflict with den's
   home-manager battery. `home-manager.extraSpecialArgs` is reserved by the
   battery and must not be set manually.
5. `hosts/sakura/default.nix` drops its `hostname`/`username` fn args
   (only `networking.hostName` consumed it; the battery `hostname` handles
   that); its `inputs` fn arg is provided by `_module.args.inputs` on the
   sakura host aspect (mirrors the pre-Den `specialArgs`).
6. `nix-index-database.nixosModules.nix-index` moved from the flake output
   list into `den.aspects.core.nixos.imports`.
7. Formatter wrapper and stateVersion defaults live in `modules/den.nix`
   and `modules/aspects.nix`.

## Consequences

### Equivalence verification (post-merge, 2026-09-13)

Both toplevels were built with `nix build --no-link --json` and compared at
the built outputs:

- **A** (pre-Den, `daac5ed`): drv `kh37knmg…`, out `c5gpwjll…`
- **B** (Den, main `4586c35`): drv `w8amlw04…`, out `x4anw5ri…`

Identical (semantics-preserving):

- **Kernel and initrd** resolve to the same store paths (6.18.40,
  `2l5dzw…bzImage` / `sjak6zw…initrd`).
- **`boot.json`** differs only in its `init`/`toplevel` self-references —
  zero semantic unit differences (unit list already verified identical).
- **HM binaries**: 696/703 bin entries in `home-manager-path` are identical
  by name and resolved package identity.

Path-swap-only noise (expected on every rebuild): `dbus session.conf`,
`dbus-broker` overrides, and `mandb.service` differ only in embedded store
hashes (`system-path`, `man-paths`), not in content semantics.

Residual 7-binary delta attributed to upstream, not Den: `cc35d92`
("route capture through the vendored upstream pipeline") replaced
`screenshot`, `screenshot-clipboard`, `screenshot-ocr`, `screenrecord`,
`screenrecord-menu`, `menu-capture` with `screenshot-edit` — a commit on
main between `daac5ed` and the merge that sakura has not deployed yet. The
equivalence claim is therefore: the Den migration itself introduces no
behavior change beyond the ordinary drift of the advancing nixpkgs input,
independent of the framework.

`flake.nix` no longer maintains parallel wiring lists; adding a host
concern is an aspect include, and adding a home feature is one import in
the ivokun aspect.

Follow-ups (deliberately deferred):

- Expose `system`/`hostname` via context (host schema) rather than the
  hardcoded `_module.args` bridges (`modules/aspects.nix`, `modules/users.nix`).
- Consider `den.batteries.unfree` to replace the blanket
  `nixpkgs.config.allowUnfree` with per-aspect unfree lists.
- The vendored scripts' two-step wiring (define in
  `packages/scripts/default.nix`, add to `home/common.nix`) is unchanged;
  a future quirk/pipe pass could make script registration single-step.

