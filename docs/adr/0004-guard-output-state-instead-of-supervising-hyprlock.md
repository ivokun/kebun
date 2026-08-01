# ADR-0004: Guard Output State Instead of Supervising the Lock Screen

## Status

Accepted

## Context

The machine intermittently came back from suspend with a black screen that swallowed every
keystroke; the only way out was holding the power button. It recurred across most of the
retained boots. Three fixes were attempted and all three failed:

- `70ab0ed` — added `hyprlock-guard`, a relaunch supervisor around hyprlock
- `7ac9918` — set `powerKey = "lock"` so a power tap would not re-suspend mid-diagnosis
- `eb4b30d` — removed a `hyprctl dispatch dpms off` chained onto `before_sleep_cmd`

Each targeted hyprlock or DPMS. The bug was in neither.

### The actual cause

`home/features/hyprland.nix` bound the lid switch to `toggle-laptop-display off`, which
runs `hyprctl keyword monitor eDP-1,disable`. On a single-panel laptop that destroys the
compositor's only `wl_output` global (`Monitor.cpp` `onDisconnect()` erases it from
`m_monitors`; `ProtocolManager` then destroys the global) and Hyprland enters unsafe
state, whose fallback output is deliberately never advertised. Clients see zero outputs.

Three mechanisms then latched the machine shut, and all three had to be true for the hang
to be unrecoverable:

1. **The undo was structurally impossible.** `toggle-laptop-display` discovered the panel
   with `hyprctl monitors -j`, which omits *disabled* monitors. So on lid open `INTERNAL`
   was empty, the script took its `notify-send "No internal display found"; exit 1` branch,
   and never reached the re-enable one line below. `SUPER+CTRL+DELETE` shared the bug, so
   the manual escape was dead in exactly the state it existed for.
2. **The session lock became un-evictable.** `SessionLockManager.cpp` computes
   `NOACTIVEMONS` with `std::ranges::all_of` over `m_monitors` — vacuously true on an
   empty list — then sends `locked` and `return`s *before* arming the 5-second
   `sendDeniedTimer`, the watchdog whose entire job is to kick a client that never commits
   a surface. `m_locked` is cleared in exactly one place (the `unlock_and_destroy` handler
   of a *non-inert* lock), and `sendDenied()` marks every replacement inert first. So a
   surfaceless hyprlock owned the lock permanently and every later instance was told
   "Seems we got yeeten".
3. **The only detector was a guaranteed false positive.** `wake-display` asserted
   `hyprctl dispatch dpms on` == `"ok"`. `Actions::dpms` skips every monitor with
   `!m_enabled` and then returns a default-constructed success, so it prints `ok` with
   every output disabled — measured to print `ok` for a nonexistent monitor name too.

Point 3 is why the previous three attempts went wrong: the one diagnostic in the system
reported "the panel is lit" in precisely the case where it was not, so every hypothesis
downstream of it pointed at hyprlock.

### Why ordering-based fixes cannot work

The final incident showed the disable is **deferred by the freeze**. `user.slice` froze
114 ms after `Lid closed.`, so the lid handler's `hyprctl` call did not run before suspend
— it landed on *resume*, 21.5 hours later:

    10:50:43.123  hyprlock 74109: onLockLocked      (a healthy lock, output bound)
    10:50:44.748  systemd-logind: Lid closed.       (1.77 s AFTER the lock succeeded)
    10:50:44.862  kernel: PM: suspend entry
    08:21:46.384  hypridle: Executing wake-display  (resume; exits, sees nothing wrong)
    08:21:46.657  removed iface 68                  (+273 ms — the deferred disable lands)
    08:21:46.714  journal ends                      (hard power-off)

Two consequences: the session was already healthily locked before the lid closed, so this
was never a lock/suspend race; and suspend can **invert** the order of the lid-close and
lid-open handlers. Any fix that relies on "off then on" ordering, or on repairing only the
lid-open path, is unsound.

The empirical signature, at 10/10 precision across the retained boots: `removed iface 68`
with no subsequent `got iface: wl_output` ⇒ that boot ends abruptly.

## Decision

Stop trying to make the lock screen survive a lost display. Make the display impossible to
lose, verify it came back, and let the lock screen recover by itself — a live lock holder
creates its surface as soon as an output returns (hyprlock `src/core/Output.cpp`, `setDone`
→ `createSessionLockSurface`).

### Configuration changes

1. **`packages/scripts/default.nix` — `toggle-laptop-display`**: discovery moves to
   `hyprctl monitors all -j` so a disabled panel stays nameable; it **refuses to disable
   the last enabled output** (`HEADLESS` excluded, since it satisfies a count without
   lighting a panel); and both directions are idempotent. The guard is re-read in the same
   process immediately before the disable, so a handler frozen mid-flight and thawed on
   resume acts on live state and degrades to a no-op. That is what makes it
   ordering-independent rather than merely lucky.
2. **`packages/scripts/default.nix` — `wake-display`**: asserts at least one monitor with
   `disabled == false` instead of matching `"ok"`, repairs with `hyprctl reload`, and takes
   a settle window (`after_sleep_cmd` passes `20`) so a disable landing after the resume
   hook is still caught.
3. **`packages/scripts/default.nix` — `hyprlock-guard`**: the relaunch loop is deleted. It
   could never fire, for two independent measured reasons — hyprlock 0.9.6 does not exit on
   the denied path (`run()` calls `exit(1)` but the process deadlocks in `exit` with 19
   threads in `futex_do_wait`, so `hyprlock || rc=$?` blocks forever and leaks a process
   per lock signal), and with `allow_session_lock_restore` off no relaunch can take the
   lock anyway. Replaced with: repair output state, `flock` for single-instance, `exec`.
4. **`hosts/common/core.nix`**: `kernel.sysrq = 240` (sync + remount-ro + signal + reboot).
   The kernel default of 16 is sync-only, so `Alt+SysRq+B` did nothing and every wedge
   ended in an unsynced power cut — which is why most of those boots have no shutdown
   markers in the journal.
5. **`home/features/hyprland.nix`**: `after_sleep_cmd` gains the settle argument, and the
   lid `bindl` pair is documented as safe-because-guarded rather than deleted.

### Repair uses `hyprctl reload`, not `keyword monitor`

Load-bearing and counterintuitive. `hyprctl keyword monitor NAME,preferred,auto,1` works
normally, but **not in the wedge**: `CMonitorRuleManager` drains rules only from the
render pre-check hook, which every render path reaches through
`CMonitorFrameScheduler::canRender()`, and that returns false while `m_unsafeState`. So it
answers `ok` and changes nothing — measured still `[]` after 6 s. Only `hyprctl reload`
recovers, because `CConfigManager::reload` calls `ensureMonitorStatus()` directly, and it
drops the runtime disable keyword by construction so it needs no name lookup.

### Rejected: `misc:allow_session_lock_restore`

Enabling it would let a fresh hyprlock take over from a *crashed* holder, closing the last
trap. Rejected to preserve the current security posture: it lets any local process lock
over the lockscreen and spoof the password prompt. It would also have required pairing with
`lockdead_screen_delay = 0`, because a takeover installs a fresh lock object whose timer
resets and `renderAllClientsForWorkspace` only suppresses the desktop while
`shallConsiderLockMissing() || clientLocked() || clientDenied()` — leaving a ~1000 ms
window where the desktop would render.

The observed hangs all had a *live* lock holder, so the display fix already covers them;
this only mattered for the crash case.

### Keeping the lid bindings

They earn their keep when docked: `lidSwitchDocked = "ignore"` means closing the lid with
an external display attached does not suspend, and switching the internal panel off is then
correct. With the last-output guard the bindings are a logged no-op in every configuration
where they were dangerous, so deletion would have cost a real feature for no additional
safety.

## Consequences

### Positive

- **The hang is prevented and recoverable.** Nothing can take the enabled-output count to
  zero, and if something does anyway, `wake-display` reloads and the live lock holder
  repaints.
- **The manual escape works.** `SUPER+CTRL+DELETE` can now re-enable a disabled panel; it
  previously could not, in exactly the state where it was needed.
- **The power button is an in-band escape hatch.** `powerKey = "lock"` (from `7ac9918`,
  whose instinct was right) routes through logind's own evdev handle, independent of
  Hyprland's input pipeline, into `lock_cmd` — which now repairs output state first.
- **Honest diagnostics.** `wake-display` reports the actual failure instead of `ok`, and
  the failure mode is greppable: `journalctl -b 0 -g "removed iface"`.
- **Less code, not more.** A relaunch loop that could not fire, plus its 40 lines of
  justification, is gone; no new script and so no new `flake.nix` / `home/common.nix`
  wiring.
- **Clean reboots as a floor.** SysRq turns the last resort from an unsynced power cut into
  a synced reboot.
- **No more duplicate locks.** `flock` collapses the repeated Lock signals hypridle raises
  when the session is already locked, which produced the "yeeten" storm and leaked a
  19-thread process each time.

### Negative

- **A crashed hyprlock is still unrecoverable in-band.** With
  `allow_session_lock_restore` off, recovery is `ssh` + `hyprctl reload`, or
  `Alt+SysRq+S,U,B`. Documented in the script; a SIGSEGV was observed once (2026-07-29).
- **Undocking with the lid shut is still a gap.** An external monitor unplugged while the
  internal panel is legitimately disabled reaches zero outputs, and nothing reconciles
  until the next resume or lock.
- **`hyprctl reload` is blunt.** It reapplies the whole config, churning every output; used
  only when there is nothing to render on, where the alternative is a reboot.
- **`wake-display` now runs for 20 s after resume.** hypridle spawns it fire-and-forget so
  nothing blocks, but it is a background process for 20 s per resume.
- **The lid bindings remain, so the trap is guarded rather than absent.** A future edit that
  bypasses `toggle-laptop-display` and calls `hyprctl keyword monitor …,disable` directly
  would reopen it.

### Neutral

- **Locking behaviour is unchanged.** Same triggers, same times; `before_sleep_cmd`,
  `inhibit_sleep = 3`, the 600 s lock listener and hyprlock's own config are untouched.
- **The 605 s `dpms off` listener stays.** DPMS keeps the monitor in `m_monitors` and the
  `wl_output` alive, so it reaches the same `NOACTIVEMONS` branch via `!m_dpmsStatus` but
  remains recoverable — a different and benign sibling of this bug.
- **The security invariant is unchanged.** Nothing here unlocks; re-enabling an output
  while locked cannot expose the desktop, because Hyprland renders only a lock surface or
  its lockdead texture while `m_locked` is set.
- **`pkgs.hyprland` (0.56.0) vs the running compositor (0.54.0) skew is untouched.** Same
  JSON schema and same `keyword`/`dispatch`/`monitors all` behaviour; hygiene for a
  separate commit.
- **Upgrading Hyprland would not have fixed this.** 0.56.0 and `main` still contain the
  `NOACTIVEMONS` early return, and they *removed* the deny watchdog.

## References

- Hyprland 0.54.0 `src/managers/SessionLockManager.cpp:98-100` — the `NOACTIVEMONS`
  shortcut (`all_of` over `m_monitors`, vacuously true when empty)
- Hyprland 0.54.0 `src/protocols/SessionLock.cpp:128` — the *only* `m_locked = false` site,
  reachable solely from a non-inert `unlock_and_destroy`
- Hyprland 0.54.0 `src/config/shared/monitor/MonitorRuleManager.cpp` and
  `src/helpers/MonitorFrameScheduler.cpp:138` (the `m_unsafeState` bail in `canRender()`) —
  together, why `keyword monitor` cannot drain in unsafe state and only `reload` works
- Hyprland 0.54.0 `src/managers/KeybindManager.cpp` (early return while `m_unsafeState`, so
  not even Ctrl+Alt+F2 is dispatched), `src/helpers/Monitor.cpp` (`onDisconnect`),
  `src/managers/ProtocolManager.cpp` (the `wl_output` global is destroyed),
  `src/render/Renderer.cpp` (the desktop is suppressed while locked)
- hyprlock 0.9.6 `src/core/Output.cpp` (`setDone` → `createSessionLockSurface`, i.e. a live
  holder repaints when an output returns) and `src/core/hyprlock.cpp:829` (the "Seems we got
  yeeten" log, on the denied path that then deadlocks in `exit`)
- [ext-session-lock-v1 protocol](https://wayland.app/protocols/ext-session-lock-v1) — the
  compositor must keep outputs blanked when the lock client disappears
- `man 5 logind.conf` — `HandleLidSwitchDocked` precedence
- Commits `70ab0ed`, `7ac9918`, `eb4b30d` (the three superseded attempts)
- Journal evidence: boot ending 2026-07-31 08:21:46 (`removed iface 68` at +273 ms into
  resume); coredump PID 12654, 2026-07-29 08:31:22 (`CRenderer::removeWidgetsFor` via
  `_CWlRegistryGlobalRemove`)

## Notes

- Date proposed: 2026-07-31
- Date accepted: 2026-07-31
- Proposed by: ivokun (reported the hang was still occurring after three fix attempts)
- Accepted by: ivokun
