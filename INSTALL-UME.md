# INSTALL-UME — ume install runbook (executed 2026-10-15)

**Status: INSTALLED 2026-10-15.** The clean reinstall described below has
run: ume is a live NixOS host (system generation 1 dates from 14:38 that
day) and the old Arch system is gone. This document is kept as the record
of the plan and its gates; it is **no longer a pre-install snapshot**, and
§2 has been updated to the post-install disk facts.

> **The install changed the NVMe's UUIDs.** `hosts/ume/` initially kept the
> pre-install values, and because `fileSystems."/boot"` then named a device
> that does not exist, the first `nh os switch` could not remount `/boot`,
> failed `local-fs.target` and dropped the machine into emergency mode.
> After any repartition, reconcile every `by-uuid` in `hosts/<name>/`
> against the live machine before switching.

## Post-install gate status (2026-10-17)

| Gate (§6 / §4.1) | Status |
|---|---|
| Services / session | ✅ `systemctl --failed` and `--user --failed` clean |
| LUKS / TPM2 | ✅ slot 0 passphrase (tested), slot 1 TPM2 (unlocks at boot); header backup taken, `age`-encrypted; off-machine copies (Drive + one more) placed by the operator. Login password **not** enrolled as a LUKS key (deliberate) |
| Storage | ✅ `/mnt/entertainments`, 32 GiB `/swap/swapfile` at prio 0 under zram 100. `/mnt/tubeinas` mounts directly over the LAN: a networkd rule (priority 5200, `suppress_prefixlength 0`) puts the connected /24 ahead of Tailscale's subnet route (table 52), which had shadowed it and broke inbound LAN services (fixed 2026-10-19). Off-LAN it falls through to the subnet route |
| Stale Arch units | ✅ none; `lan-mouse` is the kebun unit, its `pem` restored. `config.toml` came back empty (no peers authorized); the LAN peer's fingerprint was added by hand on 2026-10-19 — GUI "Authorize" does not persist |
| Calibre | ✅ ported (`services.calibre-server`, :8080, wired-LAN firewall only) |
| Apps | ✅ Moonlight, Ryubing (nixpkgs' Ryujinx successor), DaVinci Resolve (+ ROCm OpenCL). Dolphin Flatpak and DBeaver dropped |
| Borg | ✅ daily catch-up job → `borgbackups/ume` (ADR-0018); repokey export done by the operator (not machine-checked). On-site only |
| SSH | ✅ declarative keys only (`authorizedKeysInHomedir = false`), `tailscale0`-only |
| Editors | ✅ LuaLS, StyLua, rust-analyzer resolve to Nix and attach; all Mason binaries run. Rust needs a project devshell (no global toolchain, by choice) |
| Monitors | ✅ per-output rules for the LG/Lenovo stack |
| Steam 32-bit Vulkan, xpadneo, `:MarkdownPreview` | ⏳ hands-on checks pending |

This was a runbook for installing kebun on `ume` — the ASRock B550M-ITX/ac
desktop whose hardware was previously the Arch machine `ivokun-htpc`
(Omarchy 4.0.3). It records the machine's state, the decisions made before
the disk write, and the gates for the install itself.

The kebun side is already in shape: two Den hosts are wired
(ADR-0017), and `nix build
.#nixosConfigurations.ume.config.system.build.toplevel` is the build-only
validation that needs no disk changes. Partitioning, LUKS/TPM enrollment,
and activation all lie behind 【Decision Gate 1】.

**Install strategy chosen — clean reinstall (nothing has run yet; every
stage stays behind §5.1's gates):** the XPG NVMe is repartitioned with a
fresh LUKS2 (Argon2id) + Btrfs layout (2 GiB ESP + one LUKS data
partition; mapper `root`; subvolumes `@`/`@home`/`@log`; a fresh,
Btrfs-valid swapfile). The preserved-Arch-trial path is **retired**. What
this **removes** is the *accessible* old Arch system: its root filesystem
and the ESP's contents/loaders. It is **not a secure erase** — a fresh
`luksFormat` does not overwrite the entire previous payload, but after
repartitioning the old LUKS header is also **not a valid restore plan**.
The firmware NVRAM may keep a stale, unbootable `Boot0003` pointer
(firmware NVRAM is deliberately **not** touched by this runbook: no
`efibootmgr` deletion command is prescribed — firmware operations are
outside this runbook's authorization); there is therefore
**no Arch fallthrough rollback** (§7).
The chosen operator path for the install session is **local console
(keyboard/display)** with a **separate bootable rescue USB** — selected,
**not yet tested** (§5.1 stage B).

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

## 2. Disk facts (post-install, verified against the live machine 2026-10-15)

These are the values now in `hosts/ume/`. The pre-install UUIDs they
replaced (`fdfeaf01-…` LUKS, `17FE-CA36` ESP, `1ba0592d-…` Btrfs) did not
survive the repartition and exist nowhere on the machine — see the banner
at the top of this file.

- **Primary disk:** `/dev/nvme0n1` (XPG GAMMIX S70 BLADE, serial
  `2P36292DSGD7`) — LUKS2 container on `nvme0n1p2` (UUID
  `af6c38b9-e330-47b5-97dd-da19a7f29a00`) unlocking as mapper **`root`**,
  containing Btrfs (UUID `60691fd6-54bc-40ae-864a-c25e42a3307a`) with
  subvolumes `@` (`/`), `@home` (`/home`), `@log` (`/var/log`), plus a
  32 GiB Btrfs swapfile at `/swap/swapfile` inside `@` (not a separate
  mount). Compression `zstd:3` on all subvolume mounts.
- **ESP:** `/dev/nvme0n1p1`, UUID `12CE-A600` (vfat, 2 GiB, `/boot`).
- **Media disk:** `/dev/sda`, ext4, UUID
  `5a56e7ae-9a37-49c2-9a98-728c5500a08d`, automounted at
  `/mnt/entertainments` (`noauto` + `x-systemd.automount`, safe to boot
  without it).
- **`/dev/sdb` — external 477G NTFS SSD, "thumbdisk" (ADATA SX6000PNP,
  serial `2M37291155H1`, USB-attached): NEVER a target
  for any install-write tool.** The original "thumbdrive" label was
  wrong — this is a ~477G SSD. **CHOSEN as the external backup
  destination (§5), without any reformat or delete of its existing
  NTFS contents (`df` shows ~80M used).** Selected is not verified:
  capacity fit against a *measured* payload (§3) and a real
  archive-on-USB / restore-to-Linux test are still open gates. Its
  stable whole-drive identifier for the gate record:
  `/dev/disk/by-id/usb-ADATA_SX_6000PNP_012345678944-0:0` (also
  `ata-ADATA_SX6000PNP_2M37291155H1`). Stop by ID, never `/dev/sdb`
  (§7). No automatic mount/format step is
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

If installation changes partitions **or subvolume names**, **regenerate or
update this file before `nixos-install`**, using the candidate system's
actual mounted layout. Re-verify ESP UUID, LUKS UUID and mapper name,
Btrfs UUID + subvolume names, swapfile path, and that the ADATA backup
drive remains absent from the install configuration. The mapper name must stay in sync with
`boot.initrd.luks.devices."root"` in `hosts/ume/default.nix`.

## 3. Data on the machine

- **Capacity readings are dated, not reservations.** The primary
  filesystem showed 395 GiB used / 75 GiB free on 2026-10-05 and
  399 GiB used / 71 GiB free on 2026-10-08. Re-measure before installing;
  neither reading predicts the logical backup or the archive's size.
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
  For a conservative one-off migration archive, prefer no exclusions if
  the selected trees fit. If exclusions are needed, render the revised
  `home/backup.nix` policy from the installation revision and review it
  against the actual inputs: even existing cache/build/virtualenv patterns
  may match wanted data. Do not inherit the live Arch `~/.borg-excludes`,
  which stays unchanged here. Use absolute input paths; symlinks are
  archived as links, not traversed into other trees.
- **Measure the real restore size; do not size the archive from `df`.**
   Read-only measurement, 2026-10-05: `/home/ivokun` allocated
   332,708,184,064 bytes, apparent 333,081,298,081 (~310 GiB).
   On 2026-10-08 the backup disk still had ~477 GiB free and the media
   disk ~779 GiB used. Do **not** treat `df` used as an upper bound
   on the logical backup: reflinks, snapshots, compression, and dedup
   change sizes in both directions. The user-home figure does **not**
   include rootful Docker (`/var/lib/docker`) or media saves — and per
   the 2026-10-10 Docker decision (start fresh, §5.1 stage A/F), the old
   rootful Docker is now **excluded from the selected payload**; but
   wanted **bind-mount user files are not implicitly discarded** by that
   choice — each such directory must be explicitly identified in the
   off-home payload inventory, with no blanket exclusion of home/project
   trees or unknown `/var/lib` custom data (review instead). Steam's
   `libraryfolders.vdf` names `/mnt/entertainments/SteamLibrary` plus
   stale `/run/media/...` paths — verify actual live paths. The media
   library's `steamapps/compatdata` measured ~16.3 GiB on 2026-10-08;
   workshop content was ~1.1 MiB. Neither is a complete inventory of saves
   or modified games. Include wanted off-home trees as separate inputs,
   because Borg does not follow symlinks. Measure the
   *critical* payload explicitly (documents, Git trees, browser
   profiles, SSH/GPG keys, irreplaceable game saves) and record it.
- **Backup medium mechanics (chosen drive, not yet a verified gate).**
   Raw NTFS cannot preserve UNIX ownership/permissions/xattrs/symlinks
   under file-copy, so a raw home copy is *not* a restorable backup. But
   an **encrypted Borg 1.x archive stores that metadata inside archive
   bytes**, rather than as NTFS file attributes. This permits using the
   existing NTFS drive, subject to testing repository operations on that
   actual medium and restoration to Linux with appropriate privileges.
   **No reformat of
   the external ADATA drive is needed or planned**. Gates before any
   wipe: (a) create a test encrypted Borg repo on the drive, archive a
   meaningful tree containing symlinks + special permissions, (b)
   restore it to a *Linux* filesystem and verify metadata, ownership,
   and checksums. Then create and check the actual migration archive and
   restore representative Git history, documents and saves from it.
   Quiesce applications or use consistent snapshots/exports for changing
   data, especially databases. Keep the encryption key and passphrase
   recoverable independently of this PC; never record secrets here.
   Capacity fit (~477 GiB free) remains a separate, still-open check.
- **Preserve the complete checkout.** Include the entire kebun directory
  in the encrypted backup, including `.git`, local branches, untracked
  files and uncommitted edits. `git archive` omits Git history and untracked
  work; a plain clone also omits local edits and untracked work. Neither
  is the sole recovery copy. Preserve `git diff --binary HEAD` as an
  additional patch in the protected backup, and restore-test the checkout
  and its Git database on another machine before retiring this PC.
- **SSH admin access — chosen path needs no key; remote SSH is optional
  and later.** The rescue path is the **local console (keyboard/display)
  plus a tested rescue USB** (§5.1 stage B) — no additional public key is
  chosen or necessary now. The still-authorized `ivokun-htpc.pub` key is
  **unavailable as an independent rescue by default** (private keys get
  backed up by their users, but do not count on that key as a ume rescue
  path). Enabling SSH later would be deliberate hardening, only after
  (1) tailnet enrollment, (2) a surviving machine's public key
  configured and verified end-to-end, and (3) a decision on key-only SSH
  on port 22 restricted to `tailscale0`. Nothing here changes
  `modules/users.nix` today.
- **Preserved-home activation:** current HM-owned paths contain non-store
  symlinks, including `~/.config/alacritty/alacritty.toml` and files under
  `~/.config/nvim`. Home Manager refuses to clobber such symlinks even with
  `backupFileExtension = "hm-backup"`. Back them up, then move/remove every
  conflicting symlink before the first switch; never point an HM-managed
  path back into the old Arch tree.
  Under the chosen clean reinstall (§5.1 stage F), the restored data is
  merged into a **fresh NixOS home**, so the conflicting-file audit applies
  to that fresh home as preflight immediately before the first switch —
  the audit that found six conflicts is a *snapshot of a moment*:
  config-side fixes can move that set — both kebun-side fixes
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
  keep/replace/drop decision. At the NixOS handover, disable/move the
  stale units in the fresh NixOS home and verify that any replacement
  resolves to the declared unit. Cleanup happens **only in the fresh
  NixOS home after the staged data restore (§5.1 stage F)** — never in
  the currently running Arch home, and never by copying the Arch
  `~/.config/systemd/user/` files across: with clean reinstall there is
  no Arch side to roll back to (§7), so no Arch-rollback unit record is
  needed.

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
  (no `boot.resumeDevice` — hibernation is not claimed here either);
  per the 2026-10-12 decision, ume's zram runs zstd at **100%** of RAM
  (priority 100, ume-only `lib.mkForce` override) with the disk
  swapfile at priority 0 — sakura keeps its own 50%/priority-5 setup,
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
  cleanup — under a restored (fresh) home it would keep firing over a
  NixOS session if that unit file were re-copied; stage F forbids
  copying Arch user units, so the risk is only of a manual mistake.
- `calibre-content-server.service` is enabled under Arch today, serving the
  Kobo library from `/home/ivokun/Books/Calibre Library` on
  `192.168.100.26:8080`. kebun's declarative ume build does not contain it;
  record an explicit keep (port it declaratively), replace, or drop
  decision for it here. §3's stale-unit cleanup depends on this
  outcome — stage F restores data, but the unit only comes back if the
  operator ported it (the keep decision) or copied the Arch file
  against stage F's prohibition; a wiped/recreated home otherwise simply
  starts without these unit files. The keep/drop call itself may stay
  open until the apps are tested after boot — what §5.1 stage A
  requires before the wipe is that the library (and every other
  undecided item's data) is **captured in the verified archive**.
- Review the current explicit package lists before install. Proprietary or
  host-specific tools such as DaVinci Resolve, DBeaver, Moonlight, Ryujinx,
  and motherboard-control utilities are not implied by the base ume target.

Record each keep/replace/drop decision; do not discover missing workflows
only after the Arch installation is unavailable.

## 5. 【Decision Gate 1】 Partitioning & install strategy — strategy chosen, stages still gated

This runbook deliberately does **not** execute any of these steps; each
requires an explicit go decision (record what was decided in release notes
  or on paper) because the disk is real, carrying ≈ 399 GiB used / 71 GiB
  free on 2026-10-08 (§3), with no verified
backup. The strategy is chosen (clean reinstall, header note above) and the
staged plan is §5.1 — but **no destructive action is approved by these
pages**. Status of the questions below (first is decided, rest open):

- **Re-format vs. preserve — DECIDED: clean reinstall on the XPG NVMe.**
  The preserved-encrypted-filesystem trial is **retired**. What happens
  instead is a fresh GPT (2 GiB ESP `p1` + one Linux LUKS2/Argon2id data
  partition `p2`, opened as mapper `root`, fresh Btrfs with
  `@`/`@home`/`@log`) — deliberately **not** sakura's shape (no third
  swap partition, no separate `/home` or `nix` subvolumes). This removes
  the accessible old Arch system (root filesystem, ESP contents): the
  old LUKS header after repartition is **not** a valid restore plan, and
  the firmware may keep a stale `Boot0003` NVRAM pointer (no firmware
  command is prescribed here). §7 and §5.1 stage G describe what
  remains afterwards. The guard-and-write sequencing lives in
  §5.1 stage C.
  On a fresh root the swapfile must be **created for real**: the
  snapshot's path-only `swapDevices` declaration (§2) generates no
  creation service at all. Per the pinned nixpkgs `swap.nix`
  (`f35b16b14b62502a84ba8a689afe51ba290f6744`): with `size` set on a
  Btrfs device, the generated unit uses the native
  `btrfs filesystem mkswapfile --size '<size>M' --uuid clear`; the
  `dd`/`chattr` creation path is the **non-Btrfs** fallback. So NixOS
  *can* create the file when `size` is declared — but this runbook
  keeps the manual, gated fresh-file creation (+ parent directory +
  §2's extent/swapon verification) **before install and first boot**
  regardless, because boot-time creation gives no operator gate and an
  unverified extent can still fail `swapon`.
  **Swap strategy DECIDED 2026-10-12 (operator's "use the current
  strategy" after the live-Arch table):** ume-only zstd zram at 100% of
  RAM (≈ 31.3 GiB logical at the current MemTotal 33,560,952,832;
  "100%" is the zram sizing *metric*, not an assertion that zram
  reserves 100% physical RAM), zram priority **100** — implemented as
  the reviewed kebun default with ume's `lib.mkForce` 100 +
  priority-100 override, and the existing hardware-config swap-entry
  shape at priority 0 — plus a **fresh, new-file 32 GiB disk swapfile**
  (not a reflink copy carrying the ~31.3 GiB current payload: the gated
  helper runs on a fresh file), on **disk at priority 0**. No
  hibernation. Sakura keeps the shared 50% zstd capacity and nixpkgs'
  default priority 5 unchanged. None of this is a wipe or allocation
  approval; the configuration is not activated today. Do not reflink-copy the old
  swapfile.
  Btrfs refuses to snapshot a subvolume containing an active swapfile;
  any necessary `swapoff` is itself a separately authorized state change.
- **Backup path.** There is no verified
  Borg repository today, and Borg user service and `/mnt/tubeinas` are
  both failed. The external ADATA SX6000PNP (by `by-id`, §2) is
  **chosen** as the backup destination; what is NOT yet verified:
  capacity fit vs the measured critical payload (item 2) and a real
  Borg1 archive/restore on the NTFS medium (item 3). Before any wipe
  (or before "install fails at step N" is your only restore plan):
  1. **Identify the drive** by a stable identifier — model/serial-backed
      `/dev/disk/by-id/...` (§2), never a bare `/dev/sdX` name — and record
      it in the decision checklist below. (Already recorded for the
      chosen ADATA.)
  2. **Check capacity against the *measured* payload**, not `df` used
      (§3): critical payload + restore headroom must fit the drive's
      free capacity.
  3. **Restore-test a meaningful tree** through a real encrypted Borg
      archive on this NTFS medium to a Linux filesystem (“Backup
      medium mechanics”, §3) and keep the checksum from §3's
      measured-payload step as the comparison basis. A capacity check
      without a restore test is not a gate.
- **Password + LUKS keying.** Pick the system/login password deliberately.
  Before relying on the PAM fallback, add that password as a LUKS key with
  `cryptsetup luksAddKey`; the PAM hook only tries an already-enrolled key
  and cannot create one. TPM2 enrollment is separate. Plan and test both
  passphrase fallback and TPM2 unlock on the device.
  Before *any* key-slot or enrollment change, take a **LUKS header backup
  off the target disk** and verify it:

   Use `cryptsetup luksHeaderBackup` for the verified NVMe LUKS partition
   from §2, staging the image in private Linux storage and placing it in
   the encrypted off-target backup. Do not leave a plaintext header on the
   NTFS drive. Check it with `luksDump` and a SHA-256 checksum, and keep an
   independently recoverable second copy **on an independent physical
   medium** (not only the same ADATA). The image contains key slots:
   an older header can make a revoked passphrase usable again against the
   corresponding encrypted data. A readable dump/checksum is not a full
   recovery test. Test recovery only on a disposable copy of the original
   encrypted header **and data**, never by restoring a header onto the live
   NVMe or an unrelated container as a test. Recheck correspondence before
   key changes; layout/UUID comparisons alone do not prove payload recovery.
   For the clean install this applies to the **new** container: staged
   root-only (umask 077), encrypted and labeled with the **new UUID**, the
   plaintext staging copy deleted — no other key-slot or enrollment step
   precedes that capture (§5.1 stage E).
- **Account + installer passwords (gate; operator choice, not decided
  by this document).**
  On the fresh kebun boot, the `ivokun` account **starts locked**:
  `modules/users.nix` sets `initialHashedPassword = "!"` deliberately,
  and with `security.sudo.wheelNeedsPassword = true` every
  password-elevation step fails until a password exists. The chosen
  rescue path is local: console + tested rescue USB (§3, §5.1 stage B).
  Therefore the
  installer sequence must, before the first reboot:
  - **Correct `passwd` context (bug fix).** Running plain
    `passwd ivokun` in the live installer session modifies the *live*
    session's view, not the installed system's `/etc/shadow`; it is the
    wrong account. The required step, **after `nixos-install` completes
    and before the first reboot**, is:

    ```bash
    nixos-enter --root /mnt -c 'passwd ivokun'   # /mnt = explicit install target
    ```

    Never run the bare live-session `passwd ivokun` as a substitute.
    Plain `passwd ivokun` typed in the ISO session may fail outright or
    edit the live system's own context — either way it is simply the
    wrong context, and the required `nixos-enter` form above is the only
    step whose context is right.
  - **Installer/root + ivokun passwords are three distinct contexts.**
    The post-install root prompt sets the *installed* system's root —
    distinct from the live ISO's root and from ivokun, whose password is
    set by the `nixos-enter` step above **and then actually exercised**:
    an SDDM (or TTY) login and `sudo -v` after the first boot. No
    further secret-policy rule is prescribed by this runbook.
  - **Rescue_path = local console + rescue USB; no key decision is
    needed now.** §3 covers the optional, later SSH hardening (tailnet
    enrollment plus an end-to-end-verified PUBLIC key) — that choice can
    be made at any time and is not part of this install's go/no-go.
- **Boot trust.** PCR 7 TPM enrollment is unattended-unlock convenience,
  not offline-tamper resistance. Secure Boot is currently disabled and kebun
  does not provision signing keys; do not treat ume as verified boot.
- **Tailscale identity and subnet route.** `/mnt/tubeinas` points to the LAN
  address `192.168.100.29`. Its systemd unit waits for `tailscaled`, but that
  ordering does not create a route. Decide the desktop's tailnet identity and,
  if the export must work away from this LAN, verify that a subnet router
  advertises `192.168.100.0/24` and that ume accepts that route. Enrolling the
  tailnet may happen interactively (`tailscale login` browser flow) — an auth
  key is one option, and its availability/config is an open choice, not a
  requirement before the local switch.
- **Monitor layout** — keep the generic preferred rule at 1.25, or
  narrow to per-output `hl.monitor` rules (DP-1 Lenovo P27Q-40 2560x1440,
  DP-2 LG UltraFine 3840x2160) once verified on real hardware? Either
  decision is fine at install time; record it and re-confirm after first
  login.

### Decision checklist (chosen destination; remaining gates open)

Tick items as decisions actually land; this list stores decisions, not
secrets. Secrets (passphrases, keys) stay out of this repository.

- [x] **Install strategy chosen: clean reinstall** — fresh LUKS2/Btrfs
  on the XPG NVMe (§5 first bullet); old accessible system removed,
  NVRAM may keep a stale `Boot0003` pointer (no firmware command used),
  no Arch fallthrough rollback (§7). Session operator path: local
  console + keyboard/display with a separate bootable rescue USB
  (§5.1 stage B). **Selection is not a test** — the rescue USB has not
  been exercised yet.
- [x] **Backup destination chosen:** ADATA SX6000PNP, serial
  `2M37291155H1`, stable identity in §2; retain its existing NTFS contents.
- [x] **Docker decision taken (2026-10-10): start Docker fresh.**
  No migration of the old rootful Docker's containers, images,
  engine-managed volumes, databases or daemon state; the future NixOS
  runs kebun's **declared rootless Docker with new state**. **Scope is
  Docker only** — home/projects/media are not discarded by this call,
  bind-mount user files still go through the payload inventory (§3,
  §5.1 stage F), and the old Docker state stays untouched today (no
  `rm`/prune/volume commands; no backup/wipe/install execution
  authorized by this row). Remaining independent gates:
  application keep/drop (calibre, media-disk mods, other apps), the
  measured swap disk-share **capacity budget** (swap *size* is decided:
  32G, 2026-10-12), the real backup creation + restore test, and the
  rescue-USB test — all still open (§4.1, §5.1 stages A/B/C).
- [ ] **Backup capacity and repository operations** verified on that drive
  against the complete selected payload (§5 Backup path items 2–3).
- [ ] **Measured critical payload** size recorded (§3 measurement bullet).
- [ ] **Actual encrypted backup archive created** on the NTFS drive
  (whole `.git` + untracked home + chosen media state + the explicitly
  identified bind-mount user files — **not** old Docker engine state,
  per the 2026-10-10 start-fresh decision; §5.1 stage A) and
  **restore-tested to a Linux filesystem**, with checksums compared
  (§3 "Backup medium mechanics").
- [ ] **Borg key and passphrase recoverable independently** of this PC
  (§3); **pre-wipe state preservation settled** — state for every
  still-undecided item (calibre, media-disk mods, remaining apps, …)
  is captured in the archive; the keep/drop *calls* themselves may stay
  open until apps are tested after boot (§5.1 stage A).
- [ ] **Restore test** of at least one meaningful tree from the chosen
  medium, with its checksum comparison recorded (§5 Backup path item 3).
- [ ] **LUKS header backup** taken off the target disk, **stored
  encrypted** (it contains still-live keyslots), `luksDump`-verified,
  checksummed with SHA-256, with a second copy on an **independent
  physical medium** (not only the same ADATA); `luksDump`ing and
  checksumming the dump is not a recovery test (§5 Password + LUKS keying
  bullet). For the clean install the *new* container's header must be
  captured — staged private (umask 077, root-only), then encrypted into
  the archive, labeled with its **new UUID**, the plaintext staging copy
  deleted and kept off the NTFS drive — before any
  `luksAddKey`/TPM change (§5.1 stage E).
- [x] **Swap strategy selected (2026-10-12):** ume-only zstd zram at
  100% of RAM (≈ 31.3 GiB logical, priority 100 — kebun default with
  ume's `lib.mkForce` 100 / priority 100), fresh 32 GiB disk swapfile
  at priority 0 (`SWAP_SIZE=32G`), no hibernation (§5 first bullet).
  Preflight still requires the operator to set the variables
  intentionally — no defaults, no automatic run.
- [ ] **Capacity budget still open before the wipe:** measured restore
  + Nix closures + staging headroom (`BUDGET_GIB`) recorded from stage
  A and compared in §5.1 stage C's preflight against the target after
  ESP + the 32 GiB swap allocation.
- [x] **Rescue path: local console + rescue USB** — chosen; the USB boot
  test itself remains open (§5.1 stage B). Remote SSH is optional,
  later-only hardening (tailnet enrollment + verified PUBLIC key); no
  key is needed for the local path (§3, §5 account bullet). Clean
  reinstall makes the local path mandatory at first: manual LUKS
  passphrase + SDDM/TTY login + `sudo -v` must **actually work** on the
  first boot before TPM enrollment (§5.1 stage E).
- [ ] **`passwd ivokun` via
  `nixos-enter --root /mnt -c 'passwd ivokun'` confirmed** run after
  `nixos-install` and before the first reboot — not the plain
  live-session `passwd` (§5 account bullet).
- [ ] **Corrected checkout durably stored on the target and the external
  backup before unmount/reboot** (§5.1 stage D), then **separately
  restorable** from the encrypted archive (stage A/F) — `git archive`
  and raw NTFS copies are not recovery paths (§3).
- [ ] **Stale Arch user units** disposition decided via §4.1 for
  `lan-mouse.service`, `calibre-content-server.service`,
  `borg-backup.timer`; cleanup performed per §3 / §5.1 stage F.

Commands here are references, not execution approval. A staged reference
plan exists in §5.1; its human verification gates (stage A archive,
stage B rescue-USB test, per-block "go" confirmations) are still open,
so nothing in it counts as approved or final until those gates land.

## 5.1 Staged manual install plan (clean reinstall — reference, not approval)

Facts framing the plan (operator-facing, no attribution inside the gates):

- The layout shape is the ESP + LUKS2 (Argon2id) + Btrfs structure with a
  fresh, Btrfs-valid swapfile. Anything of the **old** LUKS header stays
  out of the plan: the container is fresh, and the fresh header is
  created *before* any key/TPM enrollment.
- **The repo's `stateVersion = "25.05"` is a NixOS/Home Manager state
  declaration, not an installer-ISO version.** The candidate is a recent
  UEFI x86_64 NixOS ISO (the 26.05 download is the current candidate);
  the *exact* image's checksum, and a real RX 9060 XT
  keyboard/network/rescue boot test, remain **open** — no claim in this
  doc asserts the GPU driver is proven from sources.
- The installer's filesystem generator facts quoted in stage D are read
  from the pinned nixpkgs installer source
  (`f35b16b14b62502a84ba8a689afe51ba290f6744`); primary sources are
  listed at the end of this section.

**Nothing in stages A–G has run.** Every destructive stage begins with a
**STOP gate**: running it without the operator's explicit, recorded
confirmation is a violation of this runbook. **No standalone auto-wipe
script exists or may be written, and choosing the clean strategy is not
itself approval** — the plan below is a per-block human reference, run
one gated block at a time.

### Stage A — prerequisite: an actual, restore-tested encrypted backup

- **Create the encrypted Borg archive** on the chosen ADATA NTFS drive
  (§2 identity, no reformat/delete of its contents): **entire `kebun`
  checkout including `.git`, all local branches, untracked files and
  uncommitted edits** (the current uncommitted runbook edits travel this
  way), the chosen home state and selected media state gathered in §3,
  and the **explicitly identified bind-mount user files** from the
  off-home payload inventory. Old Docker engine state is **not** an
  archive input (2026-10-10 decision, next bullet).
- **Docker is DECIDED: start fresh (2026-10-10).** Do **not** migrate
  the old rootful Docker's containers, images, engine-managed volumes,
  databases or daemon state; the future NixOS uses kebun's declared
  rootless Docker with brand-new state. The choice covers Docker only:
  keep ordinary projects/source code, Compose manifests, Dockerfiles,
  configuration and ordinary home/media files in the selected backup;
  bind-mount user files are **not** implicitly discarded — identify
  them in the home/off-home payload inventory and archive them with
  it; do not blanket-exclude `/home`/project trees or unknown
  `/var/lib` custom data without review. The old state stays untouched
  until the separately authorized install: today there are no
  `docker rm`/prune/volume commands, no backup/wipe/install execution —
  inspecting and planning are fine, writes are not. More generally: an
  open keep/drop *call* does not
  block the wipe by itself — what gates the wipe is **state
  preservation**: the data behind every still-undecided item (§4.1:
  calibre,
  media-disk mods, the other open calls) must actually be in the
  verified archive first. The 32 GiB swapfile is **not** an archive
  input — its disk share is accounted for separately in the **measured
  capacity budget**. SWAP_SIZE is DECIDED (`32G`, 2026-10-12) — what
  stays open is that budget: restore payload + Nix closures + staging
  headroom on the target after ESP + the 32 GiB swap allocation,
  checked in §5.1 preflight (§5.1 stage C).
- **Restore-test to a Linux filesystem**: extract meaningful trees from
  the archive onto a **Linux filesystem** on the rescue path or a
  surviving host — **never treat a raw NTFS copy, a `git archive`, or a
  plain clone as the restore source** (they drop metadata, history and
  untracked work; §3 "Preserve the complete checkout"). Verify
  ownership/permissions/symlinks and the §3 checksums. The fresh
  checkout that this restore produces carries the current uncommitted
  changes forward into stage D.
- **Borg key and passphrase recoverability** is verified
  *independently* of this PC (§3) before touching disks in stage C.

### Stage B — rescue and installer media (write only to the right, verified stick)

- Prepare a **separate installer/rescue USB** booting the candidate
  UEFI x86_64 ISO (26.05 is the current candidate; its exact image
  checksum and a real RX 9060 XT keyboard/network/rescue boot are still
  **open** checks). Write the image **only to a positively identified**
  USB stick (stable `by-id`, model/serial verified in the imaging
  tool): **never the ADATA backup SSD, never the MidasForce media SSD,
  never the XPG NVMe**, and never a bare ambiguous `/dev/sdX`.
- Boot that USB once on ume and test the chosen **local console +
  keyboard/display** path: key layout, **network** (wired `r8169` must
  reach everything stage D needs — or an offline `nix copy` plan must
  exist), and **disk visibility** — `lsblk -o
  NAME,SIZE,TYPE,TRAN,RM,MODEL,SERIAL` shows the XPG, media and backup
  disks while **nothing writes to any of them**. The operating loop is
  install from this USB; on any failure, reboot into the **rescue USB**
  (stage G). Until this USB boot is actually exercised, the rescue path
  stays "selected, not tested".
- **STOP gate for every disk write below:** a fresh printout of the
  target's model/serial from the stable `by-id` name (§2), confirming
  the target is not mounted, not swapped, not mapped, followed by the
  operator's explicit per-stage "go". **Optional but recommended:** once
  stage A's worth — actual archive + restorable checkout + independent
  Borg credentials — exists, physically disconnect the media SSD and
  the ADATA backup SSD during stage C; only if that never removes a
  resource still needed (until stage A completes, the media SSD may be
  the only copy of chosen state).

### Stage C — disk layout (preflight, then three separately gated write blocks)

**STOP — these blocks repartition and reformat the XPG NVMe: the
accessible old Arch system (root filesystem, ESP contents) ceases to
exist; the firmware may keep a stale `Boot0003` NVRAM pointer. Run one
block at a time, each behind its own recorded operator "go". Never paste
the whole sequence as a script; no auto-wipe file is or may be created.
If any guard fails, **stop and close the installer Bash shell** (the
guards use `exit 1` deliberately). After a closed shell, **re-run the
preflight block before another C1/C2 attempt** — its variables belong to
that shell. If C2/C3 stopped partway, resume **only** through §5.1 stage
G's explicit state inspection and a fresh recorded operator "go"; do not
repeat partitioning or formatting to recover an already-created target —
**never re-run a failed block blind.** Green guards are not a substitute
for eyes: read the printed model/serial/path lines between blocks.**

**Preflight block — non-destructive, run standalone first:**

```bash
# PREFLIGHT (non-destructive) for §5.1 stage C. Run alone; every failure
# closes this installer Bash shell via exit 1. Re-run any time.
# Variables are explicit-only — no defaults, no YES-equivalents:
: "${WIPE_CONFIRM?ERROR: WIPE_CONFIRM is unset — set it to the XPG serial}"
: "${SWAP_SIZE?ERROR: SWAP_SIZE is unset — the decided 32G (operator-decision 2026-10-12)}"
[ "$WIPE_CONFIRM" = "2P36292DSGD7" ] || { echo "STOP: WIPE_CONFIRM must be the literal serial 2P36292DSGD7"; exit 1; }
# SWAP_SIZE: strict positive base-10 GiB syntax, then the SELECTED value:
# reject empty, non-G, leading zeros (0/00/08/032G), zero — and any value
# other than the decided 32G (8G/999G cannot pass the user decision).
# Setting the variable remains an intentional operator act — no defaults,
# no automatic run:
SWAP_NUM=${SWAP_SIZE%G}
case "$SWAP_SIZE" in [1-9][0-9]*G) ;; *)
  echo "STOP: SWAP_SIZE must be a strict positive base-10 integer + G (e.g. 32G)"; exit 1;; esac
[ "$SWAP_SIZE" = "32G" ] || { echo "STOP: the decided swapfile size is 32G — '$SWAP_SIZE' cannot pass the 2026-10-12 selection"; exit 1; }
case "$SWAP_NUM" in [1-9][0-9]*|[1-9]) ;; *) echo "STOP: SWAP_NUM not positive base-10"; exit 1;; esac
# The operator verified, in person, that this session runs on the UEFI
# installer console (not from Arch or any other installed OS). Machine
# cross-checks: the live OS identifies as NixOS, and the running root is
# NOT on the target NVMe:
grep -q '^NAME="NixOS"$' /etc/os-release || { echo "STOP: session is not the NixOS installer"; exit 1; }
case "$(findmnt -n -o SOURCE /)" in *XPG_GAMMIX_S70_BLADE*) echo "STOP: running root lives on the target disk"; exit 1;; esac
# Target: the stable whole-disk by-id node, decoded column-by-column —
# never by substring-grepping a path:
DISK=/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7
test -e "$DISK" || { echo "STOP: target by-id node missing"; exit 1; }
[ "$(lsblk -dn -o TYPE "$DISK")" = "disk" ] || { echo "STOP: target is not a whole disk"; exit 1; }
[ "$(lsblk -dn -o SERIAL "$DISK")" = "2P36292DSGD7" ] || { echo "STOP: serial mismatch"; exit 1; }
# Inspect ALL descendants of the target: no mountpoints, no [SWAP], and
# no crypt/lvm/raid/md descendant may exist before a GPT is written.
# Failed inspection or no rows is a STOP, never proof of an unused disk:
DESC=$(lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$DISK") \
  || { echo "STOP: descendant inspection failed"; exit 1; }
[ -n "$DESC" ] || { echo "STOP: descendant inspection returned no rows"; exit 1; }
printf '%s\n' "$DESC"
printf '%s\n' "$DESC" | awk \
  '$3!="" || $3=="[SWAP]" || $2=="crypt" || $2=="lvm" || $2=="md" || $2 ~ /^raid/ \
   { print "STOP: unsafe descendant state: " $0; bad=1 }
   { rows++ }
   END { exit (rows ? bad : 1) }' || exit 1
swapon --show | grep -Eq 'XPG_GAMMIX_S70_BLADE|/dev/mapper/root' && { echo "STOP: target-space swap active"; exit 1; }
test ! -e /dev/mapper/root || { echo "STOP: a root mapper already exists"; exit 1; }
# /mnt: must exist as a directory, be unmounted and be empty (checked
# read-only here — the preflight writes nothing):
[ -d /mnt ] || { echo "STOP: /mnt missing"; exit 1; }
[ -z "$(findmnt -n /mnt 2>/dev/null)" ]   || { echo "STOP: /mnt is mounted"; exit 1; }
[ -z "$(find /mnt -mindepth 1 -print -quit 2>/dev/null)" ] || { echo "STOP: /mnt is not empty"; exit 1; }
# btrfs-progs >= 6.1 is REQUIRED for the native `filesystem mkswapfile`
# helper (primary source: official Btrfs documentation). Older ISO:
# stop and re-provision — no fallback helper is invented here.
btrfs --version | grep -Eq 'v(6\.[1-9][0-9]*|[7-9][0-9]*\.|[1-9][0-9]{2,}\.)' \
  || { echo "STOP: btrfs-progs 6.1+ required"; exit 1; }
# Capacity budget: the decided SWAP_SIZE=32G is not itself a capacity
# approval — the APPROVED BUDGET_GIB (measured restore payload + Nix
# closures + staging headroom, recorded from stage A/D planning) must
# fit on the target after 2 GiB ESP + 32 GiB swap:
: "${BUDGET_GIB?ERROR: BUDGET_GIB unset — approved restore+Nix-closure+staging budget in GiB}"
# BUDGET_GIB validation BEFORE arithmetic: positive base-10 integer, no
# empty/zero/leading zeros, bounded like the disk (< 500 GiB — 3 leading
# digits far exceed the capacity root, so 500+ can never be valid):
printf '%s' "$BUDGET_GIB" | grep -Eq '^[1-9][0-9]{0,2}$' \
  || { echo "STOP: BUDGET_GIB must be a positive base-10 integer without leading zeros (e.g. 420)"; exit 1; }
# WHOLE-DISK SIZE ONLY: -d prevents child rows/lines; -b gives bytes:
DISK_GIB=$(( $(lsblk -dn -b -o SIZE "$DISK") / 1073741824 ))
[ "$BUDGET_GIB" -lt "$DISK_GIB" ] \
  || { echo "STOP: budget ${BUDGET_GIB} GiB cannot exceed the ${DISK_GIB} GiB disk (capacity root)"; exit 1; }
[ $(( DISK_GIB - 2 - SWAP_NUM )) -ge "$BUDGET_GIB" ] \
  || { echo "STOP: ${DISK_GIB} GiB disk minus 2 GiB ESP minus ${SWAP_SIZE} swap is below the ${BUDGET_GIB} GiB approved budget"; exit 1; }
echo "PREFLIGHT OK — target ${DISK_GIB} GiB, ESP 2 GiB, swapfile ${SWAP_SIZE} (priority 0), budget ${BUDGET_GIB} GiB"
```

**Block C1 — partitioning. *STOP: writes a fresh GPT over the target.*
One block, one recorded operator "go":**

```bash
# C1 — PARTITIONING (destructive: new GPT).
# Recheck the preflight identity in this shell; never guess a missing target.
[ "${DISK-}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ] \
  || { echo "STOP: target changed or unset; re-run preflight"; exit 1; }
[ "${WIPE_CONFIRM-}" = "2P36292DSGD7" ] || { echo "STOP: preflight confirmation missing"; exit 1; }
CUR_TYPE=$(lsblk -dn -o TYPE "$DISK") || { echo "STOP: target type inspection failed"; exit 1; }
CUR_SERIAL=$(lsblk -dn -o SERIAL "$DISK") || { echo "STOP: target serial inspection failed"; exit 1; }
[ "$CUR_TYPE" = "disk" ] && [ "$CUR_SERIAL" = "2P36292DSGD7" ] \
  || { echo "STOP: target type or serial mismatch"; exit 1; }
# Manual re-inspection immediately before the write, read with eyes:
lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$DISK"     # unchanged since preflight
test ! -e /dev/mapper/root || { echo "STOP: root mapper appeared"; exit 1; }
# Fresh GPT: 2 GiB ESP (p1, ef00) + one LUKS data partition (p2, 8309).
# Not sakura's layout — no third swap partition, no /home or nix
# subvolumes. Combined clear+create in one call, per the official
# sgdisk manual:
sgdisk --clear --new=1:0:+2G --typecode=1:ef00 --new=2:0:0 --typecode=2:8309 "$DISK" || exit 1
udevadm settle
# Verify the new partitions by their by-id nodes: TYPE=part and
# PKNAME=the target whole disk, before ANY of them is formatted:
for P in "$DISK-part1" "$DISK-part2"; do
  test -e "$P" || { echo "STOP: $P missing after sgdisk"; exit 1; }
  [ "$(lsblk -dn -o TYPE "$P")" = "part" ] || { echo "STOP: $P wrong TYPE"; exit 1; }
  [ "$(basename "$(lsblk -dn -o PKNAME "$P")")" = "$(basename "$(readlink -f "$DISK")")" ] \
    || { echo "STOP: $P is not a child of the target disk"; exit 1; }
done
echo "C1 OK — partitions verified; operator go required before C2"
```

**Block C2 — format + open the container. *STOP: writes FAT32 and a new
LUKS2 header; the NEW passphrase typed here is every future manual
boot's.* One block, one recorded operator "go":**

```bash
# C2 — FORMAT + OPEN (destructive). cryptsetup runs WITHOUT --force or
# --batch: its prompts are part of the safety.
# Recheck the preflight identity in this shell before either format command.
[ "${DISK-}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ] \
  || { echo "STOP: target changed or unset; re-run preflight"; exit 1; }
[ "${WIPE_CONFIRM-}" = "2P36292DSGD7" ] || { echo "STOP: preflight confirmation missing"; exit 1; }
CUR_TYPE=$(lsblk -dn -o TYPE "$DISK") || { echo "STOP: target type inspection failed"; exit 1; }
CUR_SERIAL=$(lsblk -dn -o SERIAL "$DISK") || { echo "STOP: target serial inspection failed"; exit 1; }
[ "$CUR_TYPE" = "disk" ] && [ "$CUR_SERIAL" = "2P36292DSGD7" ] \
  || { echo "STOP: target type or serial mismatch"; exit 1; }
# Manual re-identity check of both partition nodes right before writing:
for P in "$DISK-part1" "$DISK-part2"; do lsblk -dn -o NAME,TYPE,SIZE "$P"; done
test ! -e /dev/mapper/root || { echo "STOP: unexpected mapper root"; exit 1; }
mkfs.vfat -F 32 -n ESP "$DISK-part1" || exit 1
cryptsetup luksFormat --type luks2 --pbkdf argon2id "$DISK-part2" || exit 1
cryptsetup open "$DISK-part2" root || exit 1
# Do not mkfs on a misresolved mapper: require a status with a resolvable
# backing device, then compare existing canonical paths (readlink -e) — the real
# node (/dev/nvme0n1p2) vs this by-id solve to different NAMES, so plain
# basename comparison can never match:
cryptsetup status root || exit 1
CS_DEV=$(cryptsetup status root 2>/dev/null | awk '/device:/ {print $2; exit}')
[ -n "$CS_DEV" ] || { echo "STOP: mapper status has no resolvable backing device"; exit 1; }
CS_REAL=$(readlink -e "$CS_DEV") || { echo "STOP: mapper device path does not resolve"; exit 1; }
PART_REAL=$(readlink -e "${DISK}-part2") || { echo "STOP: target partition path does not resolve"; exit 1; }
[ -n "$CS_REAL" ] && [ -n "$PART_REAL" ] || { echo "STOP: canonical paths came back empty"; exit 1; }
[ -b "$CS_REAL" ] && [ -b "$PART_REAL" ] || { echo "STOP: backing paths are not block devices"; exit 1; }
[ "$CS_REAL" = "$PART_REAL" ] \
  || { echo "STOP: mapper root does not back the expected partition"; exit 1; }
mkfs.btrfs -L ume-root /dev/mapper/root || exit 1
echo "C2 OK — fresh LUKS2 mapper root verified on the target; go required before C3"
```

**Block C3 — subvolumes, mounts, swapfile. *STOP: writes on the new
container.* One block, one recorded operator "go":**

```bash
# C3 — SUBVOLUMES + MOUNTS + SWAPFILE.
# Recheck the verified identity before writing to the newly created container.
[ "${DISK-}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ] \
  || { echo "STOP: target changed or unset; inspect state under stage G"; exit 1; }
[ "${WIPE_CONFIRM-}" = "2P36292DSGD7" ] || { echo "STOP: preflight confirmation missing"; exit 1; }
CUR_TYPE=$(lsblk -dn -o TYPE "$DISK") || { echo "STOP: target type inspection failed"; exit 1; }
CUR_SERIAL=$(lsblk -dn -o SERIAL "$DISK") || { echo "STOP: target serial inspection failed"; exit 1; }
[ "$CUR_TYPE" = "disk" ] && [ "$CUR_SERIAL" = "2P36292DSGD7" ] \
  || { echo "STOP: target type or serial mismatch"; exit 1; }
# After C2 the mapper exists BY DESIGN — this block asserts the expected
# present-and-correct state (not blanket absence):
test -e /dev/mapper/root || { echo "STOP: mapper root missing (C2 incomplete?)"; exit 1; }
cryptsetup status root || exit 1
CS_DEV=$(cryptsetup status root 2>/dev/null | awk '/device:/ {print $2; exit}')
[ -n "$CS_DEV" ] || { echo "STOP: mapper status has no resolvable backing device"; exit 1; }
CS_REAL=$(readlink -e "$CS_DEV") || { echo "STOP: mapper device path does not resolve"; exit 1; }
PART_REAL=$(readlink -e "${DISK}-part2") || { echo "STOP: target partition path does not resolve"; exit 1; }
[ -n "$CS_REAL" ] && [ -n "$PART_REAL" ] || { echo "STOP: canonical paths came back empty"; exit 1; }
[ -b "$CS_REAL" ] && [ -b "$PART_REAL" ] || { echo "STOP: backing paths are not block devices"; exit 1; }
[ "$CS_REAL" = "$PART_REAL" ] \
  || { echo "STOP: mapper root drifted off the expected partition"; exit 1; }
# Re-check the partition nodes and their (unmounted) input state before
# the writes:
for P in "$DISK-part1" "$DISK-part2"; do lsblk -dn -o NAME,TYPE,SIZE "$P"; done
lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$DISK-part1" "$DISK-part2"
mount /dev/mapper/root /mnt || exit 1
btrfs subvolume create /mnt/@     || exit 1
btrfs subvolume create /mnt/@home || exit 1
btrfs subvolume create /mnt/@log  || exit 1
umount /mnt || exit 1
mount -o compress=zstd:3,subvol=@     /dev/mapper/root /mnt   || exit 1
mkdir -p /mnt/{boot,home,var/log,swap}
mount -o compress=zstd:3,subvol=@home /dev/mapper/root /mnt/home    || exit 1
mount -o compress=zstd:3,subvol=@log  /dev/mapper/root /mnt/var/log || exit 1
# ESP with restrictive permissions, consistent with keeping firmware
# material tight:
mount -o fmask=0077,dmask=0077 "$DISK-part1" /mnt/boot || exit 1
# Swapfile via the official native helper (btrfs-progs >= 6.1, gated in
# preflight); size is the approved SWAP_SIZE (preflight budget):
btrfs filesystem mkswapfile --size "$SWAP_SIZE" /mnt/swap/swapfile || exit 1
chmod 0600 /mnt/swap/swapfile || exit 1
btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile || exit 1   # acceptance check
# Live test at the DECIDED promotion priority 0 (zram at priority 100 must
# stay primary); run the swapon, then the separate read-back — no hibernation:
swapon --priority 0 /mnt/swap/swapfile || exit 1
swapon --show
lsblk -nrp -o NAME,UUID "$DISK-part1" "$DISK-part2"   # record NEW ESP + container UUIDs for stage D
```

The swapfile *file* now **exists because stage C created it** — the
`swapDevices` declaration only becomes honest after real creation (§2's
"generates no creation service" note). The media SSD
(`MidasForce…QA00008000000000245`, ext4, original UUID preserved) and
the ADATA backup SSD are touched by nothing above. After C3: stage the
new container's LUKS header backup for stage E — plaintext staging is
root-only (umask 077), the archive copy is encrypted and labeled with
the NEW UUID, the plaintext staging copy is then deleted, nothing
plaintext ever reaches the NTFS drive or a chat; the second header copy
lives on an **independent physical medium**, not only the ADATA.

### Stage D — configuration: merge into the *Linux checkout*, then install

- **On the installer**, `nixos-generate-config --root /mnt` yields a
  reference `configuration.nix`/`hardware-configuration.nix`. That
  generated output is **not the final flake**, but its facts are good:
  per the pinned installer source
  (`f35b16b14b62502a84ba8a689afe51ba290f6744`), the scan **excludes
  `/dev/zram*` devices and swap *files***, captures **only filesystems
  actually mounted under `/mnt`**, and **normally detects the LUKS
  mapper `root`** (emitting `boot.initrd.luks.devices`). So the merge is
  not a rebuild: carry the detected LUKS/Btrfs/ESP/mount facts across,
  then **explicitly keep/add** the pieces the scan cannot know about:
  `swapDevices = [ { device = "/swap/swapfile"; priority = 0; } ];`
  (swap *files* are excluded from the scan, but stage C created the
  file for real — keep this declaration, **without** `size` and
  **without** any `resumeDevice`/resume offset), the media disk's
  original-UUID automount (if the media
  SSD was disconnected during install), the `compress=zstd:3` mount
  options and the `fmask/dmask=0077` ESP flags, TPM/kernel-module and
  `kebun.host.*` capability facts.
- **One LUKS container entry, not two.** `hosts/ume/default.nix`
  already declares `boot.initrd.luks.devices."root"`; keep that layout
  load-bearing in **one** place — if the scanned copy duplicates it,
  remove the duplicate and update the **existing** value with the **new
  LUKS UUID** (generated before `nixos-install`, never after). Every
  `stateVersion` line stays **25.05** — unchanged.
- **No writes happen on the editing machine now** — the new LUKS UUID
  does not exist yet, and regenerating the snapshot there would
  describe the wrong disk. The corrected configuration is produced and
  used **on the installer session**; in this repo's side nothing
  changes (no config edits, no old UUIDs).
- **Keep the corrected checkout on the target's fresh Btrfs, not in
  ISO RAM.** After C3 mounts, place the restored checkout on `/mnt`
  (or work from a surviving host's Nix store); never run builds from a
  tmpfs. Record `git status` (and `git diff --stat`) of the restored
  checkout **before and after** the machine-facts merge, so the
  preserved state is auditable.
- **Builds: pre-wipe pair on an ordinary Nix host; target-backed verify,
  not ISO-RAM.** The historical paired `nix build`
  (ume + sakura toplevels, from an Nix-having machine, no activation —
  §4's recorded 2026-09-24 milestone) validates the *shape*; after the
  facts merge, verify the corrected revision either on the **surviving
  host** or **on the target store**: `nix build --store /mnt --no-link
  .#nixosConfigurations.ume.config.system.build.toplevel` (measure
  capacity — the budget from §5.1 preflight includes closures). Do not
  try to build both hosts' closures from the ISO's RAM store — the
  installer itself builds with `nix build --store /mnt` internally, and
  that is the only build we add to the target.
- Final install, reference form: `nixos-install --root /mnt
  --no-write-lock-file --flake .#ume` (the checkout directory on
  `/mnt`, not a store copy) — this builds **only ume** into the target;
  nothing activates on the editing machine, on sakura, or anywhere
  else. The installer's root-password prompt sets the *installed*
  system's root — distinct from the live ISO root and from ivokun.
  **Before the first reboot**, run the §5 `nixos-enter --root /mnt -c
  'passwd ivokun'` step (never plain live-session `passwd`; and a
  `passwd -S` status line does not *prove* the login works — §6
  verifies an actual SDDM/TTY login).
- Future bookkeeping, for after first boot: newly imported files
  get an **explicit, narrow `git add` on that future checkout only**
  (never a bulk stage, and nothing here stages anything now):
  tracked-file changes ride inside the flake build, untracked personal
  payload travels only in the Borg archive (§3).
- Before unmounting/reboot: **store the corrected checkout durably both
  on the target and the external backup** — a checkout existing only on
  the fresh, partially-trusted box is not saved work.

### Stage E — first boot and key/password discipline

- Reboot; type the **manual LUKS passphrase** at the console — an
  **expected prompt, not a misconfiguration**: the fresh container has
  **no TPM token yet**, and the kebun config's `tpm2-device=auto`
  option (left unchanged) does **not** enroll one by itself —
  `systemd-cryptenroll` is what generates the key + JSON token
  (official systemd crypttab semantics). **No enrollment until the
  manual passphrase boot has actually been tested on this container.**
- Log in as `ivokun` at SDDM (an actual login, not a `passwd -S` line),
  then run the §6 gates: `sudo -v`, storage (`/mnt/entertainments` by
  its original UUID; `swapon --show`), session start (UWSM shell),
  clean `systemctl --failed` and `systemctl --user --failed`, and the
  native-editor checks — before declaring the install done. Note the
  accepted snapper limitation (unchanged architecture): the active
  swapfile inside `@` makes the *root* snapshot impossible, and a scrub
  may skip block groups containing the shared live swap data; `@home`
  snapshots are unaffected.
- Before any `luksAddKey` (enrolling the login password as a LUKS key)
  or TPM enrollment: capture the **new container's header backup**,
  staged root-only (umask 077), `luksDump`-verified and SHA-256-summed,
  placed **encrypted off-site and labeled with the NEW UUID**, plaintext
  staging copy deleted afterwards; keep a second copy on an
  **independent physical medium** (not only the ADATA) — §5 Password +
  LUKS keying (the image contains live keyslots; never leave plaintext
  on the NTFS drive; no secrets in chat). After each key/enrollment
  change, take the next header backup and **test a second boot's
  passphrase fallback** before treating the TPM path as primary. The
  PAM fallback never makes the login password unlock automatically — it
  only tries an **already-enrolled** key, so enrollment is an explicit
  `cryptsetup luksAddKey` (§5). PCR 7 remains convenience-only (§5
  "Boot trust").

### Stage F — data restore: separately, selectively, into the fresh home

- Restore runs **separately from the boot/config stages**: decrypt the
  **Borg repository on the ADATA NTFS drive** (that drive is not a LUKS
  container — "unlock" means the Borg repo key), extract the encrypted
  archive into an explicit **Linux staging tree**, then move *selected*
  trees into the fresh NixOS home. Staging is a **capacity problem**:
  the ~310 GiB home + a full staging copy + Nix closures would not
  assume-fit the drive's free space — extract/move **incrementally and
  selectively**, and **re-use the staging area**, never assuming the
  whole home fits twice.
  HM ownership rules apply: **never overwrite HM-managed symlink/
  generated theme/Lua config paths** (§3 preserved-activation bullet —
  non-store symlinks are the `.hm-backup`/activation-failure case), and
  **do not copy the old Arch `~/.config/systemd/user/` unit files**;
  §3's stale-unit cleanup runs afterward, **in the fresh home only**.
- Restore deliberately, per item: certificates/SSH/GPG keys, browser
  profile and saves, LAN Mouse's `pem` + peer config (§4.1). Per the
  2026-10-10 start-fresh decision, **nothing of the old rootful Docker
  is restored**: no containers/images/engine-managed volumes/databases
  or `/var/lib/docker` contents — the future kebun rootless Docker
  starts with new state. **Bind-mounted user files are ordinary files
  in the home/off-home payload inventory**: they come back with the
  ordinary selective restore of those trees — identify them explicitly
  and do not discard or blanket-exclude them because of the Docker
  choice.
- **No automatic restoration** of old system identity: `passwd`,
  `shadow`, `crypttab`, `fstab`, bootloader/EFI material, or the
  Tailscale identity — the new NixOS machine sets its own (§5 "Boot
  trust"; Tailscale identity is a §5 open question, not a restore).
- Calibre stays §4.1-open; its library travels with the ordinary home
  restore, the service does not exist until a post-boot keep/port test
  decides it.
- After the fresh home holds the restored work, the §3/HM audit cleanup
  runs **in that home only** — nothing is cleaned on the (no longer
  existing) side of the running Arch system.

### Stage G — rollback under clean reinstall

- **There is no Arch fallthrough.** After stage C, the accessible old
  system is gone — root filesystem and ESP contents; the firmware may
  still point at the (now loader-less) ESP via a stale NVRAM entry, for
  which no `efibootmgr` command is prescribed here. Failure recovery is
  one of:
  1. boot the **rescue USB**, unlock the **new** container, mount the
     **matching layout** (`@`, `@home`, `@log` and the ESP — **no
     mkfs**) and only then `nixos-enter` into the installed system to
     inspect/repair (config edits, rebuild); or
  2. if stage C failed midway, there may be **no filesystem, container
     or installed system to enter at all** — inspect what exists, take
     a **fresh explicit operator "go"**, and resume from the matching
     stage or reinstall; and
  3. once restored data has landed (stage F done), later failures are
     repaired **in the already-installed, already-restored system** —
     do **not** re-run destructive stages or wipe again without a new,
     explicit decision.
- A not-yet-captured old LUKS header is **not a data backup** (and
  repartitioning invalidates it): after the fresh `luksFormat` the
  previous payload is not recoverable through it, regardless of header
  state.
- NixOS's own rollback (`nixos-rebuild switch --rollback` or an earlier
  boot entry) needs an **earlier generation to roll back to** — after a
  successful rebuild there are two, but a machine bearing only the
  single initial generation has **no rollback target at all**; and it
  **never rolls back user data** — the external encrypted archive is
  the only data-level restore path. That is why stage A must exist
  **and be checked** before stage C's irreversible point.

**Primary sources used for the reference commands and facts in this
section** (read for the operator; nothing here executes them):

- Official NixOS manual, *Installation* — installer usage and
  `nixos-generate-config` / `nixos-install` behavior
- Official Btrfs documentation, swapfile mechanics
  (`filesystem mkswapfile`, btrfs-progs ≥ 6.1)
- Pinned nixpkgs installer source
  `f35b16b14b62502a84ba8a689afe51ba290f6744` — the filesystem/swapfile
  scan behavior quoted in stage D
- Rod Smith, `sgdisk` manual — GPT clear/typecode ordering
- systemd `crypttab` man page — what options such as
  `tpm2-device=auto` do and do not do (enrollment is
  `systemd-cryptenroll`, not the option itself)

## 6. Post-install gates (after a boot into kebun, before it's "done")

- **Services/session.** `systemctl --failed` and `systemctl --user
  --failed` are clean; UWSM session starts with SDDM; the lock PAM hook
  (`omarchy-lock-password`) exists; SUPER+K keybinding menu renders.
- **Account + passwords.** The first kebun boot is not the moment to
  discover a locked account: `passwd ivokun` must have been set via
  `nixos-enter --root /mnt -c 'passwd ivokun'` after `nixos-install`
  and before the first reboot — plain installer-session `passwd` edits
  the wrong account (§5). Verify here that the
  ivokun login works and `sudo -v` succeeds — with
  `security.sudo.wheelNeedsPassword = true`, a missing password turns
  every administrative step into a console-only rescue.
- **Editor health after first login.** Neovim is build-time-wired, but
  a successful build does not prove plugin attachment. Open throwaway
  Lua/Rust projects, run `:checkhealth` and `:LspInfo`, and verify LuaLS
  and rust-analyzer resolve to Nix tools and attach. Check StyLua formatting
  and a functional `:MarkdownPreview` after its Yarn/Node build succeeds.
  The audit proved loader incompatibility for the existing Mason LuaLS
  and StyLua binaries, not every Mason package; test the remaining tools
  needed for actual workflows too.
- **Stale Arch units.** `systemctl --user` shows none of the §3 stale
  units active: `lan-mouse.service` resolves to the kebun-declared unit
  (its `ExecStart` must not reference `/usr/bin/lan-mouse`), no
  `calibre-content-server.service` is enabled unless the §4.1 keep
  decision declared it, and `borg-backup.timer` is neither loaded nor
  firing unless a verified kebun backup design replaced it.
- **Hardware.** `amdgpu` drives the RX 9060 XT with the expected 32-bit
  Vulkan available (Steam test launch; if it aborts with the bootstrap
  error, see *Steam runtime bootstrap recovery* below); Bluetooth sees the
  Intel controller; xpadneo pairs an Xbox controller;
  `grep amdgpu /proc/modules` (or an equivalent) so no fallback mode is running.
- **TPM2/PCRs.** If LUKS TPM2 enrollment was part of install
  (`systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`), verify the
  first TPM2-unlocked boot. Separately verify that the login password was
  enrolled as a LUKS key with `cryptsetup luksAddKey` and that passphrase
  fallback still works; TPM enrollment does not add that password.
- **Monitors.** Confirm ume's `monitors.lua` matches the real layout; then
  replace the generic 1.25 preferred rule with per-output rules if that
  was the choice at Decision Gate 1 (and set `scale` per-output).
- **Remote access — optional, later hardening.** The local
  console/rescue-USB path is the chosen rescue route; SSH needs no key
  now. If SSH is added later, it comes only after tailnet enrollment
  and an end-to-end-verified PUBLIC key from another surviving machine,
  configured  key-only on port 22 restricted to `tailscale0` — and the
  old ivokun-htpc private key is not an independent rescue path either
  way (§3).
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

### Steam runtime bootstrap recovery (confirmed 2026-10-31)

Steam's main client window failed to open during the §6 hardware gate with
`Unpack runtime failed, error code 1`, then `Couldn't set up the Steam
Runtime. Are you running low on disk space?`. The `ubuntu12_32` and
`linux32` bootstrap folders were missing — including
`ubuntu12_32/steam-runtime/…` — while `steam.sh` remained and the filesystem
had over 200 GiB free. The disk-space hint was misleading.

`steam-repair-bootstrap` is the sanctioned repair. It is installed only
where NixOS Steam is enabled (gated in `home/common.nix`) and repairs from
the pinned Steam package's immutable bootstrap tarball in the Nix store,
not from the writable `~/.local/share/Steam/bootstrap.tar.xz`, which Steam
itself can replace. Run it **as ivokun, never sudo**:

```bash
nh os switch .                    # ON ume only: installs/updates the command
steam-repair-bootstrap --check    # report state; writes nothing
steam-repair-bootstrap --apply    # add-only repair
uwsm app -- steam                 # let startup/update finish
```

`--apply` only creates the missing runtime folders. It refuses an existing
target missing its structural marker files (inspect it; do not delete it)
and refuses repairs while Steam is running. This is a structural check,
not a complete runtime-integrity check. `steamapps/`, `userdata/`,
`config/`, and `steam.sh` are left untouched; `--self-test` exercises the
command against fixtures without touching the real Steam root.

The rebuild and Home Manager never mutate the Steam root automatically,
and there is no `--reset` or `rm` of the Steam root: this repairs the
current missing-bootstrap state only, not a promise against future state
deletion. Bootstrap recovery ran on ume on 2026-10-31: `--check` reported
healthy, and all 9,727 protected entries (including `steam.sh`, the local
bootstrap archive, `config/`, `userdata/`, and `steamapps/`) retained their
contents and metadata before launching Steam. A stable, visible Steam
client window and running `steamwebhelper` were subsequently verified on
ume. The Vulkan and controller gates remain separate.

## 7. Rollback and stop conditions

- **Pre-install abort:** inventory and build checks are safe now.
  Backup creation and handover cleanup described in §3 are later,
  explicitly authorized operations, not actions performed by this audit.
  A failed preparation gate is a stop, not a reason to begin installing.
- **Post-install failure:** the rollback realities are §5.1 stage G, and
  they are harsh by design. There is **no Arch fallthrough**: the clean
  reinstall removes the accessible old system (root filesystem, ESP
  contents); the firmware may retain a stale `Boot0003` NVRAM pointer,
  but there is no Arch entry to boot and no firmware command is
  prescribed. Recovery after any stage-C failure is rescue-USB →
  new-container unlock → (matching-layout mount, no mkfs) →
  `nixos-enter` repair/rebuild, or a from-scratch reinstall — where
  data comes back only from the stage A encrypted archive. NixOS
  generation rollback (`nixos-rebuild switch --rollback` or an earlier
  boot entry) needs an **earlier generation** to target, never covers
  user data, and neither substitutes for the external restore path —
  the actual backup must be verified (stage A) before stage C makes
  anything irreversible.
- **Absolute stops:** no verified restore path (§3), **no tested local
  console + rescue-USB path** (§3, §5.1 stage B), any installer-write
  target whose model/serial does not match the intended NVMe identity in
  §2, or any installer-write target resolving to the ADATA backup drive
  or the separate media disk. Device letters are not identity checks.
  Also stop for any failed systemd unit
  at post-install gate §6
  that hasn't been diagnosed.

## 8. Related reads

- `INSTALL.md` — sakura's (LUKS + BTRFS + flakes) full install guide;
  much of the installer mechanics will be the same shape, but ume is not
  a copy of that host: this runbook is authoritative for ume.
- `docs/adr/0017-model-multiple-hosts-with-host-owned-hardware.md` — the
  modeling decision behind `kebun.host` / `host-base` — the mechanism you
  see at work throughout this doc.
- `docs/adr/0013-adopt-den-aspect-oriented-framework.md` — how hosts
  compose aspects (for editing `modules/aspects.nix`).
