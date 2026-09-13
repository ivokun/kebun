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

- Verified by derivation closure comparison: package set identical
  (224 = 224), systemd unit list identical, and the residual toplevel drv
  difference is bounded to the home-manager user-env layer (man-paths,
  fish-completions, fontconfig xml, hm_files, activation chain) caused by
  Den's DAG ordering the merged lists — a benign, semantics-preserving
  delta. Deploying on sakura exercises every runtime path in one rebuild.
- `flake.nix` no longer maintains parallel wiring lists; adding a host
  concern is an aspect include, and adding a home feature is one import in
  the ivokun aspect.
- Buffers for later: expose `system`/`hostname` via context (host schema)
  rather than hardcoded `_module.args`; consider `den.batteries.unfree`
  to replace `nixpkgs.config.allowUnfree` per aspect.
