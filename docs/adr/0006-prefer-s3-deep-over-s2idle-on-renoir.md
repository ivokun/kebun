# ADR-0006: Prefer S3 (deep) over s2idle on AMD Renoir

## Status

Accepted

## Context

The machine froze three times in ten days (2026-08-01, 2026-08-04, plus one
with RTC corruption), all with the same signature: the journal ends at
`systemd-sleep: Performing sleep operation 'suspend'...` with zero kernel
output after it — a silent PM deadlock in suspend *entry*, resolved by a hard
reset. These are not wake failures; the kernel never finished going to sleep.

The smoking gun is the 2026-08-04 boot. A 10 h 24 m overnight sleep resumed
cleanly (`amdgpu: SMU is resumed successfully!`), but a second suspend was
initiated while the first resume was still in flight — kernel freeze steps
interleaved with amdgpu resume steps in the same second, and the logind
lid-triggered suspend 18 s later wedged. All three fatal suspends were
lid-triggered (`services.logind.lidSwitch = "suspend"`,
`hosts/sakura/default.nix`), two of them within ~20 s of a wake; every
successful suspend in the window was a hypridle 900 s idle timeout.

Two corroborating observations. First, after the 2026-08-01 hang the RTC read
the 2019 factory epoch at subsequent boots — the machine had hung in s2idle
until the battery flattened (or the CMOS battery is dying); NTP repaired it.
Second, an independent trap: one boot died in `hybrid-sleep` triggered by
upowerd on critical battery, despite `hosts/sakura/default.nix` documenting
hibernation as impossible (8.8 GiB LUKS swap < 30.6 GiB RAM, no
`resumeDevice`). The next boot logged `systemd-hibernate-resume: Unable to
resume from device`.

The platform was not offering a choice: the BIOS was in "Windows" sleep mode,
so `/sys/power/mem_sleep` listed only `s2idle` and the kernel reported
`ACPI: PM: (supports S0 S4 S5)`. Renoir s2idle on Linux carries a long tail of
never-fully-fixed resume hangs (PSP/SMU/platform-power sequencing; the
drm/amd class exemplified by #2362, whose 6.14 fix was reverted for
deadlocks). `acpi-cpufreq` is in use (`amd_pstate` never loads), so
amd_pstate suspend bugs are out of scope.

ADR-0004 fixed the *userspace* half of this freeze history — output-state
guards, `wake-display`, the hyprlock-guard rework (relaunch loop removed),
SysRq. This ADR is the kernel/platform half: compositor guards cannot help
when the kernel never finishes suspend entry.

## Decision

Make the machine suspend via S3 (deep) instead of s2idle, in two steps so each
is independently safe.

1. **Firmware: `Config → Power → Sleep State` flipped from "Windows 10" to
   "Linux"** (done by the user at the BIOS level on 2026-08-10, BIOS
   R1CET84W 1.53). This makes the firmware advertise S3.
2. **`hosts/common/core.nix` `kernelParams`**: added `mem_sleep_default=deep`
   with a comment block recording why. Verified post-boot:
   `cat /sys/power/mem_sleep` → `s2idle [deep]`, and the parameter is present
   in `/proc/cmdline`. The parameter landed before the BIOS flip, when deep
   was not advertised, so it was inert and safe to ship first.

Existing parameters stay and become more relevant: `acpi_sleep=nonvs` does
nothing on s2idle and only affects the S3 path, so it is now actually in play;
`amdgpu.dcdebugmask=0x10`, `amdgpu.sg_display=0` and
`rtc_cmos.use_acpi_alarm=1` are unchanged.

### Explicitly deferred

- **Closing the hibernation trap at logind/upower level**
  (`systemd.sleep.settings.Sleep.AllowHibernation = "no"`,
  `AllowHybridSleep = "no"`, `AllowSuspendThenHibernate = "no"`,
  `services.upower.criticalPowerAction = "PowerOff"`) — deferred by the user;
  the trap stays open (see Negative consequences). It remains wrong even
  under S3: `hybrid-sleep` still writes a hibernation image to the
  undersized LUKS swap first. `man 5 sleep.conf.d` for the option semantics.
- **Lid de-race** (`lidSwitch = "lock"`, letting hypridle's timeout suspend
  instead) — deferred; it would remove the fatal trigger pattern but changes
  UX, since lid close would no longer suspend immediately. Under S3 the
  suspend-during-resume race is expected to be moot; if hangs recur, this is
  the next lever.
- **s2idle A/B parameters** (`pm_async=off`, `iommu=pt`, dropping
  `processor.max_cstate=5` — AMD's own s2idle tooling flags C-state caps as
  blocking s0i3) — deferred; only relevant if forced back to s2idle.
- **Forcing S3 via ACPI FADT/DSDT initrd table override** — rejected as
  fragile: hand-maintained and broken by BIOS updates, and unnecessary since
  the firmware option exists.
- **Instrumentation if hangs recur**: `pkgs.amd-debug-tools`
  (`amd-s2idle test --count 20 --random`), `/sys/kernel/debug/amd_pmc/s0ix_stats`,
  `/sys/power/suspend_stats/last_failed_dev`.

## Consequences

### Positive

- Suspend now uses real S3 — the Renoir-reliable path per the Arch wiki for
  this exact machine generation; resume no longer depends on s0i3/PSP
  sequencing.
- `acpi_sleep=nonvs` becomes meaningful instead of inert.
- Expected end of the silent PM deadlock class: the suspend-entry freeze that
  ended three boots is an s2idle failure mode.
- Policy is unchanged: same lid and hypridle triggers, identical UX — instant
  lid suspend is still there, resume just takes ~3–5 s instead of ~1 s.

### Negative

- Resume latency increases (~1 s → ~3–5 s).
- The upower hybrid-sleep-on-critical-battery trap is still open; one more
  freeze at critical battery is possible until the deferred logind/upower
  fix lands.
- s2idle-specific mitigations (`processor.max_cstate=5`) are now dead weight
  but harmless; they stay in place to keep the revert path trivial.
- If the machine is ever lent, sold, or the BIOS is reset, the parameter goes
  silently inert again — verify with `cat /sys/power/mem_sleep`.

### Neutral

- Hibernation remains disabled-by-layout (8.8 GiB LUKS swap < 30.6 GiB RAM,
  no `resumeDevice`) exactly as documented in `hosts/sakura/default.nix`;
  this ADR does not change that. zram remains primary swap.
- ADR-0004's userspace guards remain necessary and complementary: they handle
  the compositor wedge class, this handles the kernel PM class.
- `mem_sleep_default=deep` is a no-op on any future host whose firmware does
  not advertise S3.

## References

- [Arch wiki: Lenovo ThinkPad X13 Gen 1 (AMD)](https://wiki.archlinux.org/title/Lenovo_ThinkPad_X13_Gen_1_(AMD)) — "Sleep State: Linux" enables S3
- [Arch wiki: Lenovo ThinkPad T14 (AMD) Gen 1](https://wiki.archlinux.org/title/Lenovo_ThinkPad_T14_(AMD)_Gen_1) — same BIOS option
- [Arch wiki: Power management/Suspend and hibernate](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate) — `mem_sleep_default` / MemorySleepMode
- [ADR-0004](0004-guard-output-state-instead-of-supervising-hyprlock.md) — sibling ADR, the userspace half
- [https://nyanpasu64.gitlab.io/blog/amdgpu-sleep-wake-hang/](https://nyanpasu64.gitlab.io/blog/amdgpu-sleep-wake-hang/) — the drm/amd#2362 saga: fix landed 6.14, reverted for deadlocks (drm/amd#4178); the class is still open
- `man 5 sleep.conf.d` — the deferred `Allow*` options
- Journal evidence: fatal suspends 2026-08-01 and 2026-08-04; the 2026-08-04 interleaved freeze/resume log lines; `systemd-hibernate-resume: Unable to resume from device` on the boot after the hybrid-sleep death
- `hosts/common/core.nix` — `mem_sleep_default=deep` and the surrounding parameter set
- `hosts/sakura/default.nix` — logind lid policy (`lidSwitch = "suspend"`), the hibernation-impossible comment

## Notes

- Date proposed: 2026-08-10
- Date accepted: 2026-08-10
- Proposed by: ivokun
- Accepted by: ivokun
