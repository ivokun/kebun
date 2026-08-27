# ADR-0008: Re-index elephant from NixOS user activation, not a systemd path unit

## Status

Accepted

## Context

Elephant builds its `desktopapplications` index once at startup and does not
watch for changes, so a newly installed application is invisible to walker
until the backend restarts. This surfaced with `zoom-us` (0fa1bfd): the
`.desktop` file was on disk and in `XDG_DATA_DIRS`, but SUPER+SPACE never
listed it. The `restart-walker` script (`packages/scripts/default.nix`) already
restarts both daemons by hand; the goal was to stop having to remember.

Even if elephant did watch, watching would not work here. NixOS exposes every
applications directory behind a symlink that is atomically retargeted to a new
store path on rebuild, and `inotify_add_watch` follows symlinks — a watch on
`/run/current-system/sw/share/applications` resolves to the *old* store inode
and goes stale the moment the generation flips. The directory it is watching is
immutable by construction and can never change.

`d5d08d4` tried to solve this with a `systemd.user.path` unit. Knowing
`PathChanged` would follow the symlinks and never fire, it used
`PathExistsGlob` on `*.desktop` under the three applications dirs, on the
reasoning that a glob forces systemd to watch the parent directory and
re-evaluate across renames.

That reasoning was wrong about the trigger semantics, not about the symlinks.
`PathExists*` is **level-triggered**: systemd re-evaluates the condition as soon
as the triggered unit deactivates, and re-activates it if the condition still
holds. `.desktop` files always exist under those directories, so the condition
is permanently true. The result was an unconditional restart loop, gated only
by the unit's own `ExecStartPre=sleep 2`:

```
12:56:47 Finished Restart elephant to re-index desktop applications.
12:56:47 Starting Restart elephant to re-index desktop applications...
12:56:49 Finished ...
12:56:49 Starting ...          ← every 2 s, indefinitely
```

Elephant was therefore never up for more than two seconds, and every walker
invocation raced a restarting backend. Two smaller defects rode along: the
third watched path,
`/home/${username}/.local/state/nix/profiles/profile/share/applications`, does
not exist on this machine (nothing here is installed with `nix profile`), and
the `sleep 2` was a guess at when activation settles rather than a real
ordering constraint — the system profile symlink is swapped *before*
`switch-to-configuration` updates `/etc` and `/run/current-system`, so a
profile-triggered restart can race ahead of the files it is meant to pick up.

There is no edge-triggered path condition that fits. `PathChanged` /
`PathModified` are edge-triggered but blind to symlink swaps; `PathExists*` sees
the swap but never stops firing. Watching a real parent directory that does
change (`/nix/var/nix/profiles`) would fire on the *profile* bump, which is the
wrong moment — too early, and unordered with respect to activation.

## Decision

Delete `systemd.user.paths.elephant-reindex` and
`systemd.user.services.elephant-reindex`. Restart elephant from a NixOS user
activation snippet instead, in `hosts/common/desktop.nix`:

```nix
system.userActivationScripts.elephant-reindex = ''
  ${pkgs.systemd}/bin/systemctl --user try-restart elephant.service || true
'';
```

`system.userActivationScripts` runs inside the user session via
`nixos-activation.service`, which `switch-to-configuration` restarts explicitly
on every switch — after the new `/etc` and `/run/current-system` are in place.
That is a real ordering guarantee rather than a sleep, and it is the use case
nixpkgs documents for the option ("rebuilding the .desktop file cache for
showing applications in the menu").

`try-restart` rather than `restart`, so the snippet is a no-op when elephant is
not running (headless boot, activation before `graphical-session.target`).
`|| true` keeps a failure from marking the whole activation degraded.

The trade is coverage: this fires on system activation only. It does not cover
`nix profile install`, which the old glob nominally watched. That is acceptable
— this machine is fully declarative, has no user profile
(`~/.local/state/nix/profiles/profile` does not exist), and `restart-walker`
remains for the ad-hoc case.

## Consequences

### Positive

- Elephant stays up. Before the fix it restarted every ~2 s and burned CPU
  re-indexing continuously; now it restarts once per `nh os switch`.
- Newly installed applications appear in walker after a rebuild with no manual
  step, which was the original goal of `d5d08d4`.
- The restart is correctly ordered against activation instead of racing it
  behind a fixed sleep, so the index is guaranteed to see the new generation.
- Two units and a `coreutils` reference drop out of the closure; the mechanism
  is now three lines in the file that already holds the rest of the elephant
  config.

### Negative

- Applications installed outside a rebuild (`nix profile install`, an unpacked
  AppImage dropping a `.desktop`) still need `restart-walker`. Nothing watches
  for them.
- Every `nh os switch` restarts elephant whether or not the application set
  actually changed. The restart is cheap and the alternative — diffing the
  `.desktop` set — is not worth the machinery.
- Walker loses its backend for the moment of the restart. Pressing SUPER+SPACE
  during activation can fail.

### Neutral

- `systemd.user.services.elephant.path` from `5e79508` is untouched and still
  required; it fixes activation (`Exec=` resolution), which is a separate
  failure from indexing.
- Recovery from the loop needed a manual `systemctl --user stop
  elephant-reindex.path elephant-reindex.service` in the live session — NixOS
  removes the unit files from `/etc/systemd/user` on switch but does not stop
  units that are already running in a user session.

## References

- `hosts/common/desktop.nix` — `services.elephant.enable`, the unit `path`
  override from `5e79508`, and the activation snippet this ADR adds
- `d5d08d4` — the `PathExistsGlob` path unit this ADR reverts
- `5e79508` — sibling elephant fix: `PATH` for `Exec=` resolution
- `packages/scripts/default.nix` — `restart-walker`, the manual escape hatch
- `man 5 systemd.path` — `PathExists`/`PathExistsGlob` are re-checked on
  deactivation of the triggered unit; `PathChanged`/`PathModified` are inotify
  edges
- `nixos/modules/system/activation/activation-script.nix` —
  `system.userActivationScripts`, run by `systemd.user.services.nixos-activation`
  ("switch-to-configuration restarts this explicitly on every switch")
- Journal evidence: `journalctl --user -u elephant-reindex.service`, 2026-08-27
  12:54–12:59, one activation every ~2 s
- Elephant 2.22.0, walker 2.x, both from nixpkgs

## Notes

- Date proposed: 2026-08-27
- Date accepted: 2026-08-27
- Proposed by: Salahuddin Muhammad Iqbal (with Claude Code)
- Accepted by: ivokun
