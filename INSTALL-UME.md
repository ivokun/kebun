# INSTALL-UME — ume install runbook (config-first, no disk changes yet)

**Status: PRE-INSTALL. Nothing in this document has run destructive
commands, and none is approved by writing it here.** This is a runbook for
installing kebun on `ume` — the ASRock B550M-ITX/ac desktop whose hardware
is currently the editing machine `ivokun-htpc` (Arch + Omarchy 4.0.3). It
records the machine's *current* state, the decisions that must be made
*before* any disk write, and the gates for the install itself.

The kebun side is already in shape: two Den hosts are wired
(ADR-0017), and `nix build
.#nixosConfigurations.ume.config.system.build.toplevel` is the build-only
validation that needs no disk changes. Partitioning, LUKS/TPM enrollment,
and activation all lie behind 【Decision Gate 1】.

---

## 1. Machine inventory (ume)

| Item | Value |
|---|---|
| Board | ASRock B550M-ITX/ac (B550, AM4) |
| CPU | AMD Ryzen 9 5900X (Vermeer, `kvm-amd`) |
| GPU | AMD Radeon RX 9060 XT (Navi 44, `amdgpu`, 32-bit Mesa enabled for Steam) |
| Ethernet | Realtek RTL8111/8168 (`r8169`), primary wired link |
| Wi-Fi / BT | Intel AC 3168 (`btusb`; Wi-Fi driver per firmware set) |
| TPM | TPM2 present; configured for LUKS auto-unlock after enrollment (`tpm_crb`/`tpm_tis` in initrd) |
| Role | Desktop (`kebun.host.isLaptop = false`), Steam + xpadneo + Flatpak |

Build declared in `hosts/ume/default.nix`; disk snapshot in
`hosts/ume/hardware-configuration.nix`.

## 2. Current disk facts (pre-install snapshot — may change on install)

Recorded verbatim from the live machine into
`hosts/ume/hardware-configuration.nix`:

- **Primary disk:** `/dev/nvme0n1` — LUKS2 container (UUID
  `fdfeaf01-6060-473f-9d01-dfd685d2e2fd`) unlocking as mapper **`root`**,
  containing Btrfs (UUID `1ba0592d-e0e2-44dc-a8cb-6dec12f4b417`) with
  subvolumes `@` (`/`), `@home` (`/home`), `@log` (`/var/log`), plus a
  Btrfs swapfile at `/swap/swapfile`.
  Compression `zstd:3` on all subvolume mounts.
- **ESP:** UUID `17FE-CA36` (vfat, `/boot`).
- **Media disk:** `/dev/sda`, ext4, UUID
  `5a56e7ae-9a37-49c2-9a98-728c5500a08d`, automounted at
  `/mnt/entertainments` (`noauto` + `x-systemd.automount`, safe to boot
  without it).
- **`/dev/sdb`: a removable NTFS thumbdrive ("thumbdisk"). NEVER a target.
  It is deliberately not configured anywhere in kebun; keep it that way
  and triple-check any `dd`/`parted`/`mkfs` device argument.**

If install repartitions, **regenerate this file**:
`nixos-generate-config --show-hardware-config` from the installed system
(or diff by hand), and re-verify — ESP UUID, LUKS UUID and mapper name,
Btrfs UUID + subvolume names, swapfile path, and that `/dev/sdb` is still
absent from the config. The mapper name must stay in sync with
`boot.initrd.luks.devices."root"` in `hosts/ume/default.nix`.

## 3. Data on the machine

- **`/home` ≈ 290 GiB evaluable payload; the root Btrfs (with snapshots
  machinery aside) has ≈ 380 GiB used overall.** Size your restore path
  against the *380 GiB used* figure, not the 290 GiB one.
- **There is currently no verified backup.** The existing Borg user
  service on this machine is in **failed** state, the `/mnt/tubeinas`
  NFS mount is **failed**, and `.borg-excludes` excludes `Downloads`
  (~69 GiB). Do not treat any of these as a restore path.
- Verify independently, with your own eyes and checksums, that
  everything required to live on this desktop survives somewhere else:
  check Downloads, Documents, Work, Projects, game state on `/mnt/entertainments`
  (that disk is *not* being wiped — but confirm before assuming), browser
  profiles, SSH/GPG keys, and anything else the excludes decided for you.
- **This machine is being replaced.** The repo itself usually lives here:
  **commit and push the kebun repo, then clone it fresh on sakura (or
  elsewhere) and confirm the clone is complete before proceeding.** Do
  not wipe the only checkout copy.
- **SSH admin access:** only `ivokun-htpc.pub` is an authorized key today.
  If that host is the one being wiped, add and verify an admin key from
  *another surviving machine* (or retain physical/console access with a
  known password). Without this, a botched install locks you out of
  remote rescue.
- **Preserved-home activation:** current HM-owned paths contain non-store
  symlinks, including `~/.config/alacritty/alacritty.toml` and files under
  `~/.config/nvim`. Home Manager refuses to clobber such symlinks even with
  `backupFileExtension = "hm-backup"`. Back them up, then move/remove every
  conflicting symlink before the first switch; never point an HM-managed
  path back into the old Arch tree.

**Stop condition:** if any of the verification above cannot be completed,
do not proceed past this section. Nothing has been touched yet; this is
the cheapest possible place to abort.

## 4. Build-only validation (safe now — no root, no disk writes)

From the kebun checkout on any Nix-having machine (e.g. sakura, which is
already kebun-managed and in remote reach):

```bash
nix fmt                              # alejandra formatter
nix build .#nixosConfigurations.ume.config.system.build.toplevel
```

`ume` is composable — the same shared aspects as sakura (`host-base`,
`core`, `desktop`, `dev`, `networking`, `printing`, `snapper`,
`shell-entry`) plus `hosts/ume/`. Differences to eyeball in the built
system:

- Steam enabled, xpadneo enabled, Flatpak enabled, no laptop-only
  battery/lid/touchpad logic, swap lives on `/swap/swapfile`
  (no `boot.resumeDevice` — hibernation is not claimed here either),
- the ext4 media disk automount at `/mnt/entertainments`, the NFS Tailscale
  automount `/mnt/tubeinas`,
- `monitors.lua` has ume's generic preferred/auto rule at scale 1.25;
  replace with per-output rules once booted on real hardware,
- LAN Mouse is packaged as a graphical-session user service and UDP 4242 is
  open only on ume's wired LAN links, not arbitrary Wi-Fi networks.

**Verification gate:** the sakura build
(`.#nixosConfigurations.sakura...`) must still be green — restructure of
shared aspects must not perturb the deployed host (ADR-0017's gate).
Re-check both builds before anything destructive.

Recorded 2026-09-24: both full toplevel closures built successfully during
the config-first work. This records the milestone, not a waiver: rebuild both
from the exact revision chosen for installation.

### 4.1 Application and user-state parity still to decide

The buildable host is not a claim that every Arch/AUR application or every
runtime state directory has been migrated:

- LAN Mouse's service is declarative, but its private
  `~/.config/lan-mouse/lan-mouse.pem` and peer authorization config are not
  put in the Nix store. Back them up securely and restore them after install.
- Flatpak support is enabled, but the current Dolphin Emulator Flatpak must
  be installed/restored separately.
- The failed Borg user timer/script is intentionally not copied into kebun.
  Choose and test a repository and secret-management design before adding a
  scheduled backup.
- Review the current explicit package lists before install. Proprietary or
  host-specific tools such as DaVinci Resolve, DBeaver, Moonlight, Ryujinx,
  and motherboard-control utilities are not implied by the base ume target.

Record each keep/replace/drop decision; do not discover missing workflows
only after the Arch installation is unavailable.

## 5. 【Decision Gate 1】 Partitioning & install strategy — NOT yet approved

This runbook deliberately does **not** execute any of these steps; each
requires an explicit go decision (record what was decided in release notes
or on paper) because the disk is real, carrying ~380 GiB, with no verified
backup. Options and open questions:

- **Re-format vs. preserve.** Two candidate paths:
  1. **Preserve existing layout** (LUKS + Btrfs as-is): install kebun
     into the existing Btrfs/LUKS. This avoids repartitioning but is still
     an in-place OS migration with real data-loss risk; it requires the
     snapshot in `hardware-configuration.nix` to remain authoritative and
     an explicit plan for the Arch root, `/boot`, and existing home data.
  2. **Re-check/re-partition** (as with sakura's install): clean
     subvolumes, possibly a different LUKS layer/PCRs. More work, more
     risk; the snapshot is then authoritative only until regeneration.
  The decision here drives every later step. This runbook intentionally
  chooses neither path; select one only after the backup gate is satisfied.
- **Backup path** (section 3's unresolved item). There is no verified
  Borg repository today, and Borg user service and `/mnt/tubeinas` are
  both failed. Decide where the 290–380 GiB restore copy lives, *and test
  a restore of at least one meaningful tree*, before any wipe (or
  before "install fails at step N" is your only restore plan).
- **Password + LUKS keying.** Pick the system/login password deliberately.
  Before relying on the PAM fallback, add that password as a LUKS key with
  `cryptsetup luksAddKey`; the PAM hook only tries an already-enrolled key
  and cannot create one. TPM2 enrollment is separate. Plan and test both
  passphrase fallback and TPM2 unlock on the device.
- **Boot trust.** PCR 7 TPM enrollment is unattended-unlock convenience,
  not offline-tamper resistance. Secure Boot is currently disabled and kebun
  does not provision signing keys; do not treat ume as verified boot.
- **Tailscale with what idents?** `/mnt/tubeinas` autos-mounts through
  `x-systemd.requires=tailscaled.service`; decide the tailscale identity
  for this desktop (fresh host? reuse the existing arch one's name?) and
  have an auth key ready before first switch, so the NFS automount can
  come up.
- **Monitor layout** — keep the generic preferred rule at 1.25, or
  narrow to per-output `hl.monitor` rules (DP-1 Lenovo P27Q-40 2560x1440,
  DP-2 LG UltraFine 3840x2160) once verified on real hardware? Either
  decision is fine at install time; record it and re-confirm after first
  login.

No destructive command appears here and none is implied. Once this gate is
cleared, the *full, exact* install steps (partitioning or
preservation commands, LUKS/TPM enrollment, installer-built
`nixos-generate-config` update) are their own written-down-before-running
step — not a retro-fit of this list.

## 6. Post-install gates (after a boot into kebun, before it's "done")

- **Services/session.** `systemctl --failed` and `systemctl --user
  --failed` are clean; UWSM session starts with SDDM; the lock PAM hook
  (`omarchy-lock-password`) exists; SUPER+K keybinding menu renders.
- **Hardware.** `amdgpu` drives the RX 9060 XT with the expected 32-bit
  Vulkan available (Steam test launch); Bluetooth sees the Intel
  controller; xpadneo pairs an Xbox controller; `grep amdgpu /proc/modules`
  (or an equivalent) so no fallback mode is running.
- **TPM2/PCRs.** If LUKS TPM2 enrollment was part of install
  (`systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`), verify the
  first TPM2-unlocked boot. Separately verify that the login password was
  enrolled as a LUKS key with `cryptsetup luksAddKey` and that passphrase
  fallback still works; TPM enrollment does not add that password.
- **Monitors.** Confirm ume's `monitors.lua` matches the real layout; then
  replace the generic 1.25 preferred rule with per-output rules if that
  was the choice at Decision Gate 1 (and set `scale` per-output).
- **Remote access.** SSH is reachable with the admin key from another
  surviving machine. Restoring the old ivokun-htpc private key may preserve
  its identity, but authorizing that key on ume alone does not provide an
  independent rescue path.
- **LAN Mouse.** Restore `~/.config/lan-mouse/lan-mouse.pem` and its peer
  authorization config before the first remote-control session; confirm the
  service listens only on the intended wired network.
- **Storage state.** `/mnt/entertainments` mounts; `/mnt/tubeinas` mounts
  and stays mounted over Tailscale (it was failed on Arch — re-verify from
  scratch on NixOS).
- **`hardware-configuration.nix` regenerated/verified** per section 2,
  and the resulting `nix build
  .#nixosConfigurations.ume.config.system.build.toplevel`
  re-evaluates green. After this, ume's record in this repo is
  post-install truth, not a snapshot.

## 7. Rollback and stop conditions

- **Pre-wipe abort:** sections 1–4 are all read-only/evaluate-only. Any
  failure there is a "stop and re-think", not a recovery.
- **Post-install failure:** write the rollback path for the selected disk
  strategy before running it. Preserving Arch is useful only if its root and
  boot entry are both deliberately retained and tested. A NixOS generation
  rollback (`nixos-rebuild switch --rollback` or an earlier boot generation)
  exists only after a successful NixOS installation; it is not a substitute
  for an external restore path.
- **Absolute stops:** no verified restore path (§3), no verified admin key
  on another machine (§3), any hint that the installer is reaching a device
  named `/dev/sdb`, or any failed systemd unit at post-install gate §6 that
  hasn't been diagnosed.

## 8. Related reads

- `INSTALL.md` — sakura's (LUKS + BTRFS + flakes) full install guide;
  much of the installer mechanics will be the same shape, but ume is not
  a copy of that host: this runbook is authoritative for ume.
- `docs/adr/0017-model-multiple-hosts-with-host-owned-hardware.md` — the
  modeling decision behind `kebun.host` / `host-base` — the mechanism you
  see at work throughout this doc.
- `docs/adr/0013-adopt-den-aspect-oriented-framework.md` — how hosts
  compose aspects (for editing `modules/aspects.nix`).
