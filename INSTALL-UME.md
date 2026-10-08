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

- **Primary disk:** `/dev/nvme0n1` (XPG GAMMIX S70 BLADE, serial
  `2P36292DSGD7`) — LUKS2 container (UUID
  `fdfeaf01-6060-473f-9d01-dfd685d2e2fd`) unlocking as mapper **`root`**,
  containing Btrfs (UUID `1ba0592d-e0e2-44dc-a8cb-6dec12f4b417`) with
  subvolumes `@` (`/`), `@home` (`/home`), `@log` (`/var/log`), plus a
  Btrfs swapfile at `/swap/swapfile` inside `@` (not a separate mount).
  Compression `zstd:3` on all subvolume mounts.
- **ESP:** UUID `17FE-CA36` (vfat, `/boot`).
- **Media disk:** `/dev/sda`, ext4, UUID
  `5a56e7ae-9a37-49c2-9a98-728c5500a08d`, automounted at
  `/mnt/entertainments` (`noauto` + `x-systemd.automount`, safe to boot
  without it).
- **`/dev/sdb` — external 477G NTFS SSD, "thumbdisk" (ADATA SX6000PNP,
  serial `2M37291155H1`, USB-attached, currently empty): NEVER a target
  for any install-write tool.** The original "thumbdrive" label was
  wrong — this is a ~477G SSD. And since the external-disk backup
  approach was chosen in principle (§5), it is the only external drive
  currently on the desktop and thus the leading *candidate* for that
  path; still NOT a verified/selected one. Its by-id / by-UUID
  identifier for the gate record:
  `/dev/disk/by-id/usb-ADATA_SX_6000PNP_012345678944-0:0` (also
  `ata-ADATA_SX6000PNP_2M37291155H1`). No automatic mount/format step is
  prescribed here — mounting (read-only where possible) and any
  filesystem work happen behind explicit gates only.
- **Never trust bare `/dev/sdX` names in destructive commands.** The
  stable identifiers live in `/dev/disk/by-id/` and are pinned above:
  system NVMe `nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7` (+`-part2` for
  the LUKS container), media disk
  `ata-MidasForce_SSD_1TB_QA00008000000000245`, external SSD
  `usb-ADATA_SX_6000PNP_012345678944-0:0`. sdX letters reorder when USB
  disks are plugged in a different order, so **re-verify with
  `lsblk -o NAME,SIZE,TYPE,TRAN,RM,MODEL,SERIAL` immediately before any
  destructive command.**

A read-only audit on 2026-09-28 confirmed that `/swap/swapfile` was active on
the current Arch system and resolved through the `@` root mount. The Nix file
records only its path, not the Btrfs extent properties required for swap. After
any install-time disk change, and before relying on it, verify that the file is
still active and that Btrfs accepts it as NODATACOW, preallocated, and
single-device:

```bash
swapon --show
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

The second command is read-only and verifies the Btrfs swapfile requirements;
its printed resume offset does not enable hibernation by itself.

If install repartitions, **regenerate this file**:
`nixos-generate-config --show-hardware-config` from the installed system
(or diff by hand), and re-verify — ESP UUID, LUKS UUID and mapper name,
Btrfs UUID + subvolume names, swapfile path, and that `/dev/sdb` is still
absent from the config. The mapper name must stay in sync with
`boot.initrd.luks.devices."root"` in `hosts/ume/default.nix`.

## 3. Data on the machine

- **`/home` ≈ 290 GiB evaluable payload; the root Btrfs (with snapshots
  machinery aside) has ≈ 380 GiB used overall.** Historical eval-time
  figures; the live read in *this* snapshot is 395 GiB used / 75 GiB free
  (measurement bullet below). Neither figure is a backup-size estimate.
- **There is currently no verified backup.** The existing Borg user
  service on this machine is in **failed** state, the `/mnt/tubeinas`
  NFS mount is **failed**, and `.borg-excludes` excludes `Downloads`
  (~69 GiB). Do not treat any of these as a restore path.
  (`.borg-excludes` here is the *Arch* file on this machine, not the
  repo's `home/backup.nix`; the two are similar but distinct — repo-side
  excludes are managed separately and this runbook makes no claim that
  the Arch file was already changed.)
- Verify independently, with your own eyes and checksums, that
  everything required to live on this desktop survives somewhere else:
  check Downloads, Documents, Work, Projects, game state on `/mnt/entertainments`
  (that disk is *not* being wiped — but confirm before assuming), browser
  profiles, SSH/GPG keys, and anything else the excludes decided for you.
- **Measure the real restore size; do not size the archive from `df`.**
  The current root Btrfs reads **395 GiB used / 75 GiB free** in this
  snapshot (older figures: ~290 GiB payload / ~380 GiB used). Both
  figures include re-downloadables — game caches, installers, thumbnails
  —, so treat them as an *upper bound*. Measure the
  *critical* payload separately (documents, Git trees, browser
  profiles, SSH/GPG keys, irreplaceable game saves) and choose an
  external drive whose *free capacity* exceeds that payload — not merely
  apportioned from `df`'s used figure. If the chosen backup target is the
  external SSD ("thumbdisk", §2), its ~477 GiB counts only as a raw
  ceiling: NTFS allocates MFT records dynamically (no fixed inode
  budget), and an NTFS target cannot faithfully hold Linux ownership,
  permissions, xattrs, or symlinks for a file-by-file restore. So a
  restore test *through this medium* is mandatory before trusting it —
  or the gate decision must choose a Linux-native filesystem for the
  drive (a fresh-wipe decision, never made here).
- **This machine is being replaced.** The repo itself usually lives here:
  **commit and push the kebun repo, then clone it fresh on sakura (or
  elsewhere) and confirm the clone is complete before proceeding.** Do
  not wipe the only checkout copy.
- **SSH admin access:** only `ivokun-htpc.pub` is an authorized key today.
  If that host is the one being wiped, add and verify an admin key from
  *another surviving machine* (or retain physical/console access with a
  known password). Without this, a botched install locks you out of
  remote rescue. This runbook's key choice here is candidate — not a
  finished — decision; the key identity, machine, and the slot reserved
  for it in `modules/users.nix` (or a second key file) must still be
  settled and the key verified end-to-end before the gate ("Decision
  Gate 1") closes.
- **Preserved-home activation:** current HM-owned paths contain non-store
  symlinks, including `~/.config/alacritty/alacritty.toml` and files under
  `~/.config/nvim`. Home Manager refuses to clobber such symlinks even with
  `backupFileExtension = "hm-backup"`. Back them up, then move/remove every
  conflicting symlink before the first switch; never point an HM-managed
  path back into the old Arch tree.
  The latest preflight audited six conflicting paths as a *snapshot of a
  moment*: config-side fixes can move that set — both kebun-side fixes
  and any pre-switch removal of a conflicting link change the answer —,
  so re-run the audit as preflight immediately before the first switch;
  do not treat the six as a complete or frozen list, do not hardcode the
  current set into an install script, and never point an HM-managed path
  back into the old Arch tree.
- **Stale Arch user units.** The `~/.config/systemd/user/` tree carries
  several Arch-era units that remain deployed (and in some cases enabled):
  `lan-mouse.service` (enabled, pointing to `/usr/bin/lan-mouse` —
  a path that does not exist on NixOS; a declarative LAN Mouse unit
  already exists in kebun, but such a user-unit file would shadow that),
  `calibre-content-server.service` (enabled, binding `192.168.100.26`),
  and `borg-backup.timer` (enabled, firing at 03:00 daily). None of the
  unit *files* seen here is a kebun unit; §4.1 owns their
  keep/replace/drop decision. Before the first switch, explicitly
  disable each and move its unit file out of the live tree (or confirm
  the equivalent function is already declaratively ported to kebun) so
  no stale Arch unit stays active over a NixOS session; do not leave
  them dangling.

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
- the ext4 media disk automount at `/mnt/entertainments`, the LAN-addressed NFS
  automount `/mnt/tubeinas` (remote use needs a Tailscale subnet route),
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
  Note the interaction with §3's stale-unit finding: the Arch
  `~/.config/systemd/user/lan-mouse.service` hardcodes
  `/usr/bin/lan-mouse` and shadows the declarative unit if left in place
  — revealed here so both stops (stale-unit removal and pem restore)
  appear in this same checklist, not in two unrelated sections.
- Flatpak support is enabled, but the current Dolphin Emulator Flatpak must
  be installed/restored separately.
- The failed Borg user timer/script is intentionally not copied into kebun.
  Choose and test a repository and secret-management design before adding a
  scheduled backup. Its enabled `borg-backup.timer` (03:00 daily, up to
  30 min randomized delay) is one of the stale units in §3's stale-unit
  cleanup — under a preserved home it keeps firing over a NixOS session
  if not disabled.
- `calibre-content-server.service` is enabled under Arch today, serving the
  Kobo library from `/home/ivokun/Books/Calibre Library` on
  `192.168.100.26:8080`. kebun's declarative ume build does not contain it;
  record an explicit keep (port it declaratively), replace, or drop
  decision for it here. §3's stale-unit cleanup depends on this
  outcome — and the whole §3 stale-unit bullet matters specifically for
  a preserved home; a wiped/recreated home simply starts without these
  unit files.
- Review the current explicit package lists before install. Proprietary or
  host-specific tools such as DaVinci Resolve, DBeaver, Moonlight, Ryujinx,
  and motherboard-control utilities are not implied by the base ume target.

Record each keep/replace/drop decision; do not discover missing workflows
only after the Arch installation is unavailable.

## 5. 【Decision Gate 1】 Partitioning & install strategy — NOT yet approved

This runbook deliberately does **not** execute any of these steps; each
requires an explicit go decision (record what was decided in release notes
or on paper) because the disk is real, carrying ≈ 395 GiB used / 75 GiB
free in this snapshot (§3), with no verified
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
     On a fresh root the swapfile must also be **created for real**: the
     snapshot's path-only `swapDevices` declaration (§2) generates no
     creation service at all — nixpkgs only emits the `mkswap-…` unit
     when `size` is set (or random encryption is enabled). Adding `size`
     would create the file automatically (`truncate` + `chattr +C` +
     `dd` + `mkswap`), but that path silently tolerates a failed
     `chattr +C`, and on a compressed Btrfs `@` an extent without
     NODATACOW fails `swapon` with "Invalid argument" at boot; the
     declaration also assumes the parent directory already exists.
     Prefer a deliberate, Btrfs-aware manual creation (size chosen,
     NODATACOW confirmed) before the first rebuild, with the declaration
     merely enabling it either way, and verify with §2's read-only
     checks. Do not assume an arbitrary-size patch makes the path-only
     declaration valid by itself.
  The decision here drives every later step. This runbook intentionally
  chooses neither path; select one only after the backup gate is satisfied.
- **Backup path** (section 3's unresolved item). There is no verified
  Borg repository today, and Borg user service and `/mnt/tubeinas` are
  both failed. An external-disk backup is the chosen *approach* in
  principle; the exact target is not yet resolved. Before any wipe (or
  before "install fails at step N" is your only restore plan):
  1. **Identify the drive** by a stable identifier — model/serial-backed
     `/dev/disk/by-id/...` (§2), never a bare `/dev/sdX` name — and record
     it in the decision checklist below. The existing external NTFS SSD
     (ADATA SX6000PNP, ~477 GiB) is a candidate, not a decision.
  2. **Check capacity against the *measured* payload**, not `df` used
     (§3): critical payload + restore headroom must fit the drive's
     free capacity, with the filesystem's inode/small-file model
     verified on the drive rather than assumed from one `df` line.
  3. **Restore-test a meaningful tree** from the chosen medium and keep
     the checksum from §3's measured-payload step as the comparison
     basis. A capacity check without a restore test is not a gate.
- **Password + LUKS keying.** Pick the system/login password deliberately.
  Before relying on the PAM fallback, add that password as a LUKS key with
  `cryptsetup luksAddKey`; the PAM hook only tries an already-enrolled key
  and cannot create one. TPM2 enrollment is separate. Plan and test both
  passphrase fallback and TPM2 unlock on the device.
  Before *any* key-slot or enrollment change, take a **LUKS header backup
  off the target disk** and verify it:

  ```bash
  # Reference only — run behind this gate, not before. Device argument is
  # the pinned by-id path from §2; the output file lives on the chosen
  # external backup medium (mounted deliberately, never automounted).
  cryptsetup luksHeaderBackup /dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7-part2 \
    --header-backup-file <external-drive-mount>/ume-luks-header.img
  cryptsetup luksDump <external-drive-mount>/ume-luks-header.img   # verify readable
  sha256sum <external-drive-mount>/ume-luks-header.img             # record in notes
  ```

  The header copy is itself sensitive: **it contains key slots that are
  later revoked**, and restoring it resurrects them, so it can undo
  access revocation if it leaks. Store it off the target disk (the
  external backup medium), treat it like a password-equivalent, and make
  a second copy. This is the recovery path for a botched
  `luksAddKey`/`luksKillSlot`/re-enrollment — without it, a key-slot
  mistake is unrecoverable.
- **Account + installer passwords (gate; operator choice, not decided
  by this document).**
  On the fresh kebun boot, the `ivokun` account **starts locked**:
  `modules/users.nix` sets `initialHashedPassword = "!"` deliberately,
  and with `security.sudo.wheelNeedsPassword = true` every
  password-elevation step fails until a password exists. SSH with the
  still-authorized key (`keys/ivokun-htpc.pub`) could technically reach
  that locked account — but that key belongs to the machine being
  replaced, so it is not an independent rescue path. Therefore the
  installer sequence must, before the first reboot:
  - Use a **separate installer-session password** for the install/root
    environment — never reuse or derive the (future) ivokun login
    password for it.
  - Run `passwd ivokun` **from the installer session, before the first
    reboot** — otherwise the fresh boot has no working local login and
    no password-capable sudo, and the only remote path there would be
    the dying machine's own SSH key (§3), which the independent-rescue
    rule explicitly rejects.
  - Decide the **admin-key** substitution while the installer session is
    still open: the only authorized key in the repo today
    (`modules/users.nix` → `keys/ivokun-htpc.pub`) belongs to the machine
    being replaced, so a rescue key from another surviving machine (or a
    retained console/password path) must be chosen and verified before
    that machine is gone (§3's SSH admin access bullet).
- **Boot trust.** PCR 7 TPM enrollment is unattended-unlock convenience,
  not offline-tamper resistance. Secure Boot is currently disabled and kebun
  does not provision signing keys; do not treat ume as verified boot.
- **Tailscale identity and subnet route.** `/mnt/tubeinas` points to the LAN
  address `192.168.100.29`. Its systemd unit waits for `tailscaled`, but that
  ordering does not create a route. Decide the desktop's tailnet identity and,
  if the export must work away from this LAN, verify that a subnet router
  advertises `192.168.100.0/24` and that ume accepts that route. Have the
  required auth key ready before the first switch.
- **Monitor layout** — keep the generic preferred rule at 1.25, or
  narrow to per-output `hl.monitor` rules (DP-1 Lenovo P27Q-40 2560x1440,
  DP-2 LG UltraFine 3840x2160) once verified on real hardware? Either
  decision is fine at install time; record it and re-confirm after first
  login.

### Decision checklist (placeholders — no decision is complete yet)

Tick items as decisions actually land; this list stores decisions, not
secrets. Secrets (passphrases, keys) stay out of this repository.

- [ ] **Backup target drive** identified by a stable `by-id`/model+serial
  identifier, recorded here; capacity checked against the measured
  critical payload, not `df` used (§5 Backup path items 1–2).
- [ ] **Measured critical payload** size recorded (§3 measurement bullet).
- [ ] **Restore test** of at least one meaningful tree from the chosen
  medium, with its checksum comparison recorded (§5 Backup path item 3).
- [ ] **LUKS header backup** taken off the target disk, verified with
  `luksDump`, hashed, stored on the backup medium with a second copy
  (§5 Password + LUKS keying bullet).
- [ ] **Preserve vs. fresh** strategy chosen (first bullet of this
  section).
- [ ] **Swapfile plan** for the fresh path only: deliberate size +
  Btrfs-aware creation method + §2 verification commands (option 2).
- [ ] **Admin rescue key** chosen from a surviving machine and verified
  end-to-end; the currently authorized `ivokun-htpc.pub` dies with its
  host (§3, §5 account bullet).
- [ ] **Installer-session password** distinct from the ivokun login
  password; `passwd ivokun` confirmed run from the installer session
  *before* the first reboot (§5 account bullet).
- [ ] **Stale Arch user units** disposition decided via §4.1 for
  `lan-mouse.service`, `calibre-content-server.service`,
  `borg-backup.timer`; cleanup performed per §3.
- [ ] **Arch rollback retention plan** recorded: old root + Limine boot
  entry retained and tested, home state recoverable (§7).

No destructive command appears here and none is implied. Once this gate is
cleared, the *full, exact* install steps (partitioning or
preservation commands, LUKS/TPM enrollment, installer-built
`nixos-generate-config` update) are their own written-down-before-running
step — not a retro-fit of this list.

## 6. Post-install gates (after a boot into kebun, before it's "done")

- **Services/session.** `systemctl --failed` and `systemctl --user
  --failed` are clean; UWSM session starts with SDDM; the lock PAM hook
  (`omarchy-lock-password`) exists; SUPER+K keybinding menu renders.
- **Account + passwords.** The first kebun boot is not the moment to
  discover a locked account: `passwd ivokun` was required from the
  installer session before the first reboot (§5). Verify here that the
  ivokun login works and `sudo -v` succeeds — with
  `security.sudo.wheelNeedsPassword = true`, a missing password turns
  every administrative step into a console-only rescue.
- **Stale Arch units.** `systemctl --user` shows none of the §3 stale
  units active: `lan-mouse.service` resolves to the kebun-declared unit
  (its `ExecStart` must not reference `/usr/bin/lan-mouse`), no
  `calibre-content-server.service` is enabled unless the §4.1 keep
  decision declared it, and `borg-backup.timer` is neither loaded nor
  firing unless a verified kebun backup design replaced it.
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
  service listens only on the intended wired network, and that the
  running unit is the kebun one (§6 stale-units gate), not a surviving
  Arch file pointing at `/usr/bin/lan-mouse`.
- **Storage state.** `/mnt/entertainments` mounts. `/mnt/tubeinas` mounts on
  the LAN; if remote access is required, repeat the check away from the LAN to
  prove the Tailscale subnet route rather than only the service ordering. It
  was failed on Arch, so re-verify it from scratch on NixOS. Confirm
  `/swap/swapfile` appears in `swapon --show` and that the read-only
  `btrfs inspect-internal map-swapfile -r` check above succeeds.
- **`hardware-configuration.nix` regenerated/verified** per section 2,
  and the resulting `nix build
  .#nixosConfigurations.ume.config.system.build.toplevel`
  re-evaluates green. After this, ume's record in this repo is
  post-install truth, not a snapshot.

## 7. Rollback and stop conditions

- **Pre-wipe abort:** sections 1–4 are all read-only/evaluate-only. Any
  failure there is a "stop and re-think", not a recovery.
- **Post-install failure:** write the rollback path for the selected disk
  strategy before running it. Preserving Arch is useful only if its root
  and boot entry are both deliberately retained and **tested** — the
  Limine entry (`Boot0003` in `efibootmgr`, `limine.conf` on the ESP) is
  part of that plan, and the old home must stay recoverable for an Arch
  relaunch. Note this rollback is an *Arch* rollback (reboot into the
  retained Limine entry), not a NixOS generation rollback (`nixos-rebuild
  switch --rollback` or an earlier boot generation), which exists only
  after a successful NixOS installation — and neither substitutes for an
  external restore path.
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
