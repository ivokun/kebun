---
id: 202610142100_kebun_ume_installation_and_post_installation
title: Kebun - Ume Installation and Post-Installation
tags:
  - note
  - kebun
  - nixos
  - installation
status: installed
date: 2026/10/14
---

# Kebun - Ume Installation and Post-Installation

> **Status: installed 2026-10-15.** ume is live (system generation 1 dates from 14:38 that day). These were the instructions; they are kept as the record of the plan.
>
> **One post-install step in Phase 6 did not reach the repo.** The UUID merge below was applied to the install-time copy under `/mnt/etc/nixos/kebun` — which is why generation 1 boots correctly — but those edits were "uncommitted by design" and never made it into the working clone, and the durable `/etc/nixos/kebun` fallback the runbook describes does not exist on the installed system. `hosts/ume/` therefore kept the pre-install UUIDs until 2026-10-15, when the first `nh os switch` hit a `/boot` device that does not exist, failed `local-fs.target` and dropped the machine into emergency mode. The real values are now in the repo and recorded in the table below.

Canonical source: [INSTALL-UME.md @ 56ac7a6a](https://github.com/ivokun/kebun/blob/56ac7a6a7a23a373b5211cc2eb31d8d249fa74aa/INSTALL-UME.md). Repo: [ivokun/kebun](https://github.com/ivokun/kebun).

## Table of Contents

- What This Note Is
- What Gets Installed and What Is Preserved
- Risks and Stop Rules
- Before You Start
- Phase 1 — Boot the Installer
- Phase 2 — Clone the Pinned Configuration
- Phase 3 — Partition the Target NVMe
- Phase 4 — ESP and LUKS2
- Phase 5 — Btrfs Subvolumes, Mounts, and Swap
- Phase 6 — Merge Machine Facts
- Phase 7 — Install NixOS and Set the User Password
- Phase 8 — Unmount and Reboot
- Phase 9 — First Boot Checks
- Phase 10 — Restore Data Selectively
- Optional — TPM and LUKS Login Key Later
- Recovery
- Operational Checklist
- Primary Sources

## What This Note Is

Reinstall guide for **ume** — the ASRock B550M-ITX/ac desktop (Ryzen 9 5900X, RX 9060 XT) — as a kebun/NixOS host: live installer from the HP v210w USB, then the freshly installed system.

Everything runs in **one Bash terminal**, one block at a time (installer shell; after first boot you switch to `bash` explicitly — the login shell is fish). Every destructive block is a **guarded child Bash** (`env -u BASH_ENV -u ENV bash --noprofile --norc -c 'set -euo pipefail; …'`): checks run inside the child, any failure stops it **before** a write, and your terminal stays alive. Never run these blocks in the background, and never paste the next block until a native prompt returns. Any command error means **STOP and inspect** — no blind retries, no mass cleanup or reformat after an error.

## What Gets Installed and What Is Preserved

- **Erase target (only):** `/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7` — XPG GAMMIX S70 BLADE, serial `2P36292DSGD7`, 512110190592 bytes. Never address disks by `sdX`/`nvmeXn1` letters.
- **Preserved, never formatted:** media SSD (Midas Force 1TB, serial `QA00008000000000245`, ext4 UUID `5a56e7ae-9a37-49c2-9a98-728c5500a08d`, at `/mnt/entertainments`) and the ADATA SX6000PNP backup SSD (serial `2M37291155H1`, NTFS UUID `083A183749A0AEE1`) holding the Borg repository. Optionally disconnect them physically **after** the config source is secured and the ADATA is safely unmounted/ejected — never a raw unplug; keep the media UUID in the merged config even if detached.
- **New layout:** GPT = 2 GiB ESP (vfat, `fmask=0077,dmask=0077`) + remainder as LUKS2 (Argon2id) opened as mapper `root`, holding Btrfs subvolumes `@` `/`, `@home` `/home`, `@log` `/var/log`, all `compress=zstd:3`. Swap = new 32G Btrfs swapfile at `/swap/swapfile` (priority 0) plus ume's already-decided zram (100% of RAM, priority 100; sakura stays 50%/5 — unchanged).
- **Config source:** public git clone of kebun pinned to `56ac7a6a7a23a373b5211cc2eb31d8d249fa74aa` (complete tracked install configuration). Fallback only if git/network fails: the Borg `ume-checkout-20261014T001037Z` archive (whole working tree at pre-commit HEAD `93ef6fe2…` with `.git` and untracked files; it does not itself check out 56 — file bytes match).

## Risks and Stop Rules

- **Clean repartition — no Arch fallback.** The old Arch system stops being bootable at Phase 3; recovery data comes only from the Borg archive.
- **Not a secure erase.** Reformatting does not overwrite the whole previous payload; the old LUKS header is not a restore plan.
- **Never wipe from the running system.** The current Omarchy/Arch root cannot wipe the disk it runs from; only the installer session does Phase 3+.
- **Identity is never waived.** Exact by-id target + serial + byte size + NixOS-live/UEFI + unused state are re-checked in every guarded child before any write.
- **NVRAM:** `boot.loader.efi.canTouchEfiVariables = true` allows the installer to write EFI boot variables. Do not manually delete NVRAM entries; do not claim "firmware untouched".
- **Restore headroom is unmeasured** — a known, accepted risk. Historical home measurements were ≈ 333 GB; the selected archive is ≈ 356 GB logical including other inputs. Neither is a fit proof for restored data + Nix + swap + staging. Check free space and restore incrementally.
- **Fast-track decisions stand:** archive cutoff 2026-10-12 (later changes may be missing); whole home + selected off-media items archived; Steam's ~747 GiB library unarchived but kept on the media SSD; Docker starts fresh; unassessed off-home bind mounts accepted.
- **Protect the backup and media disks** — never a write target. No secrets (passphrases, keys, header images) belong in this vault.

## Before You Start

Already true (checked in the final checklist):

- **Backup:** Borg 1.4.5 repository on the ADATA NTFS drive — path `…/thumbdisk/kebun-pre-ume-20261012T105721Z-327b41a6/borg`, repo ID `89b6e628…`. Data archive `home-and-saves-20261012T105721Z` (ID `95ad3501…`): **integrity/authentication check + representative restore passed — not a full-OS image**. Owner holds the key/passphrase physically, separately from this vault; the old "encrypted key open" item is superseded — do not reopen it.
- **Full checkout archive:** `ume-checkout-20261014T001037Z` (ID `ea99ac67…`) — whole working tree (`.git`, tracked, untracked), native extract dry-run passed. Config fallback only.
- **Git:** install revision pushed — `56ac7a6a…` on `main`/`origin`; the five tracked files match the archived sources. Repo is public; neither route modifies it.
- **Installer USB:** HP v210w — serial `000000000000003F`, capacity 8076132352 bytes — NixOS 26.05 UEFI installer, boot-tested (UEFI, keyboard, network). Keep it as the rescue USB.
- **This note is not proof of anything** — update the checklist only after real results.

## Phase 1 — Boot the Installer

Boot the HP USB in UEFI mode, pick the installer, log in, open a terminal, and become root with `sudo -i` — keep this one terminal for Phases 2–8.

Get the tool set **before** anything else. Fetching packages writes into the live system's Nix store — it is not an activation or format step, and no install target is touched:

```bash
nix-shell -p git gptfdisk parted cryptsetup btrfs-progs dosfstools nano util-linux systemd borgbackup
```

`parted` provides `partprobe`; `util-linux`/`systemd` keep `lsblk`, `findmnt`, `blkid`, `mount`, `swapon`, `udevadm` available; `borgbackup` (1.4.x) serves the optional config fallback. Stay in this shell for Phases 2–8.

Define the variables, then run the live-state child (exported values are re-verified against hardcoded literals in every child):

```bash
export TARGET=/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7
export WIPE_CONFIRM=2P36292DSGD7
export REV=56ac7a6a7a23a373b5211cc2eb31d8d249fa74aa
export FALLBACK_REV=93ef6fe2acc46c0078fc9669e3b83238aa966d2f
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
[ "${WIPE_CONFIRM:?export WIPE_CONFIRM first}" = "2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
TYPE=$(lsblk -dn -o TYPE "$NODE"); [ "$TYPE" = disk ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /)
case "$ROOT_FS" in tmpfs|overlay) ;; *) echo "STOP: unexpected live root fstype: $ROOT_FS" >&2; exit 1;; esac
DESC=$(lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$TARGET")
if [ -z "$DESC" ]; then echo "STOP: no lsblk rows for target" >&2; exit 1; fi
while read -r N T MP; do
  [ -n "$N" ]; [ -z "$MP" ]; case "$T" in disk|part) ;; *) exit 1;; esac
  H=/sys/class/block/${N##*/}/holders; [ -d "$H" ]
  HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
done <<< "$DESC"
SWAPS=$(swapon --show=NAME --noheadings)
if [ -n "$SWAPS" ]; then while read -r SW; do
  SW_NODE=$(readlink -e "$SW"); [ -n "$SW_NODE" ]
  case "$SW_NODE" in "$NODE"|"$NODE"p*) exit 1;; esac
done <<< "$SWAPS"; fi
if [ -e /dev/mapper/root ]; then echo "STOP: mapper root already exists" >&2; exit 1; fi
[ -d /mnt ]
[ ! -L /mnt ]
INV_TARGETS=$(findmnt -rn -o TARGET)
if [ -z "$INV_TARGETS" ]; then echo "STOP: findmnt inventory empty" >&2; exit 1; fi
while read -r MT; do [ "$MT" != /mnt ]; done <<< "$INV_TARGETS"
PROBE=$(find /mnt -mindepth 1 -printf x -quit)
if [ -n "$PROBE" ]; then echo "STOP: /mnt not empty" >&2; exit 1; fi
echo "live-state checks OK"
'
```

Live-session zram or other RAM swap is fine — only swap backed by the target is rejected. If anything stops, do not continue.

## Phase 2 — Clone the Pinned Configuration

```bash
CFG=$(mktemp -d /tmp/kebun-ume-install.XXXXXXXX)
export CFG
export MODE=git
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
CFG=${CFG:?export CFG first}
REV=${REV:?export REV first}
[ -d "$CFG" ]
start_empty=$(find "$CFG" -mindepth 1 -printf x -quit)
if [ -n "$start_empty" ]; then echo "STOP: CFG dir not empty" >&2; exit 1; fi
git clone https://github.com/ivokun/kebun.git "$CFG"
git -C "$CFG" checkout --detach "$REV"
HEAD_NOW=$(git -C "$CFG" rev-parse HEAD)
if [ "$HEAD_NOW" != "$REV" ]; then echo "STOP: HEAD $HEAD_NOW is not $REV" >&2; exit 1; fi
[ -f "$CFG/flake.nix" ]
[ -f "$CFG/flake.lock" ]
echo "clone OK — config source ready before any erase"
'
```

Clone failure means stop — the checkout never runs (no unintended repo checkout), and nothing is erased without a config source (see [Recovery](#recovery)).

**Fallback (only if git/network is unavailable).** With ADATA connected and normally mounted, run the physical-drive/repository identity block in Phase 10 step 2 first (it also works in this live root shell). Borg 1.4.x is available in the tool shell. Extract only the checkout subtree into a fresh private Linux directory; no Git inspection of restored metadata:

```bash
umask 077
STAGE=$(mktemp -d /tmp/fallback-cfg.XXXXXXXX)
export STAGE
export REPO="${ADATA_MNT:?run Phase 10 identity steps first}/kebun-pre-ume-20261012T105721Z-327b41a6/borg"
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
REPO=${REPO:?export REPO first}
STAGE=${STAGE:?export STAGE first}
[ -d "$REPO" ]
[ -d "$STAGE" ]
CANON=$(readlink -e "$STAGE"); [ "$CANON" = "$STAGE" ]
MODE_NOW=$(stat -c %a "$STAGE"); [ "$MODE_NOW" = 700 ]
OWNER=$(stat -c %u "$STAGE"); UID_NOW=$(id -u); [ "$OWNER" = "$UID_NOW" ]
FS=$(findmnt -rn -T "$STAGE" -o FSTYPE); case "$FS" in tmpfs|btrfs|ext4|xfs) ;; *) exit 1;; esac
EMPTY=$(find "$STAGE" -mindepth 1 -maxdepth 1 -printf x -quit); [ -z "$EMPTY" ]
cd "$STAGE"
borg extract --show-rc "$REPO::ume-checkout-20261014T001037Z" "home/ivokun/Documents/dev/kebun"
'
```

```bash
export CFG="$STAGE/home/ivokun/Documents/dev/kebun"
export MODE=borg
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
CFG=${CFG:?export CFG first}
[ -d "$CFG/.git" ]
[ -f "$CFG/flake.nix" ]
[ -f "$CFG/flake.lock" ]
cd "$CFG"
printf "%s\n" \
"da3c51b55f69ea3bbfdfbaca6581bac7a9063c616b816bda97f01bae5eb7f526  flake.lock" \
"84318ec4a44d505575e9ac00731ca90541f592499b008b6693038da79bff4a81  INSTALL-UME.md" \
"ffee6da5fd4424dfff4dad3aac5c66b521dfb82df6605955d4a1b382770a92e0  hosts/ume/default.nix" \
"2f3ee47604a5197db1d67b54ebc55c3731405385cf3abc4e1983493eafaedd27  hosts/ume/hardware-configuration.nix" \
"dd3d8d9198f925270f4a00ca7203225152e3753c31276e2892a769828b2a1180  home/features/editors.nix" \
"2b36f51a4f7c3c04158a0bb38c3d5fe62d328b50d52348444890b0f9c5c62f6d  home/nvim/lua/plugins/plugins.lua" | sha256sum --check --status
echo "fallback six recorded file digests OK; Git metadata not executed or validated"
'
```

Require extraction exit 0/no warnings before verification. The fallback needs no
commit 56 — only the six recorded digests and file presence. Without either
config source, stop before Phase 3. Stop if a recorded filename/digest differs;
do not substitute another file or bypass the proof.

## Phase 3 — Partition the Target NVMe

**Destructive: fresh GPT over the target — the old system disappears here.** Checks fail → the write never runs. One block, one explicit go.

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
[ "${WIPE_CONFIRM:?export WIPE_CONFIRM first}" = "2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
TYPE=$(lsblk -dn -o TYPE "$NODE"); [ "$TYPE" = disk ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
CFG=${CFG:?export CFG first}
MODE=${MODE:?export MODE first}
[ -d "$CFG/.git" ]
[ -f "$CFG/flake.nix" ]
[ -f "$CFG/flake.lock" ]
case "$MODE" in
  git) HEAD_NOW=$(git -C "$CFG" rev-parse HEAD); [ "$HEAD_NOW" = "56ac7a6a7a23a373b5211cc2eb31d8d249fa74aa" ] ;;
  borg)
    cd "$CFG"
    printf "%s\n" \
    "da3c51b55f69ea3bbfdfbaca6581bac7a9063c616b816bda97f01bae5eb7f526  flake.lock" \
    "84318ec4a44d505575e9ac00731ca90541f592499b008b6693038da79bff4a81  INSTALL-UME.md" \
    "ffee6da5fd4424dfff4dad3aac5c66b521dfb82df6605955d4a1b382770a92e0  hosts/ume/default.nix" \
    "2f3ee47604a5197db1d67b54ebc55c3731405385cf3abc4e1983493eafaedd27  hosts/ume/hardware-configuration.nix" \
    "dd3d8d9198f925270f4a00ca7203225152e3753c31276e2892a769828b2a1180  home/features/editors.nix" \
    "2b36f51a4f7c3c04158a0bb38c3d5fe62d328b50d52348444890b0f9c5c62f6d  home/nvim/lua/plugins/plugins.lua" | sha256sum --check --status ;;
  *) echo "STOP: MODE must be git or borg" >&2; exit 1 ;;
esac
DESC=$(lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$TARGET")
if [ -z "$DESC" ]; then echo "STOP: no lsblk rows for target" >&2; exit 1; fi
while read -r N T MP; do
  [ -n "$N" ]; [ -z "$MP" ]; case "$T" in disk|part) ;; *) exit 1;; esac
  H=/sys/class/block/${N##*/}/holders; [ -d "$H" ]
  HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
done <<< "$DESC"
SWAPS=$(swapon --show=NAME --noheadings)
if [ -n "$SWAPS" ]; then while read -r SW; do
  SW_NODE=$(readlink -e "$SW"); [ -n "$SW_NODE" ]
  case "$SW_NODE" in "$NODE"|"$NODE"p*) exit 1;; esac
done <<< "$SWAPS"; fi
if [ -e /dev/mapper/root ]; then echo "STOP: mapper root already exists" >&2; exit 1; fi
[ -d /mnt ]
[ ! -L /mnt ]
INV_TARGETS=$(findmnt -rn -o TARGET)
if [ -z "$INV_TARGETS" ]; then echo "STOP: findmnt inventory empty" >&2; exit 1; fi
while read -r MT; do [ "$MT" != /mnt ]; done <<< "$INV_TARGETS"
PROBE=$(find /mnt -mindepth 1 -printf x -quit)
if [ -n "$PROBE" ]; then echo "STOP: /mnt not empty" >&2; exit 1; fi
sgdisk --clear --new=1:0:+2G --typecode=1:ef00 --new=2:0:0 --typecode=2:8309 "$TARGET"
partprobe "$TARGET"
udevadm settle
for P in "$TARGET-part1" "$TARGET-part2"; do
  PN=$(readlink -e "$P"); [ -b "$PN" ]
  TYPE=$(lsblk -dn -o TYPE "$PN"); [ "$TYPE" = part ]
  PARENT=$(lsblk -dn -o PKNAME "$PN"); [ "$PARENT" = "${NODE##*/}" ]
  MOUNTS=$(lsblk -dn -o MOUNTPOINTS "$PN"); [ -z "$MOUNTS" ]
done
P1_SZ=$(lsblk -bdn -o SIZE "$TARGET-part1"); [ "$P1_SZ" = "2147483648" ]
P2_SZ=$(lsblk -bdn -o SIZE "$TARGET-part2")
if [ "$P2_SZ" -lt 400000000000 ]; then echo "STOP: partition 2 too small" >&2; exit 1; fi
echo "partition OK — p1 2GiB ESP, p2 remainder"
'
```

If the child stops after `sgdisk` (geometry/nodes wrong), do not re-run `sgdisk` to "fix" it — inspect state per [Recovery](#recovery).

## Phase 4 — ESP and LUKS2

ESP format (guarded; result verified):

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
TYPE=$(lsblk -dn -o TYPE "$NODE"); [ "$TYPE" = disk ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
P="$TARGET-part1"
PN=$(readlink -e "$P"); [ -b "$PN" ]
TYPE=$(lsblk -dn -o TYPE "$PN"); [ "$TYPE" = part ]
PARENT=$(lsblk -dn -o PKNAME "$PN"); [ "$PARENT" = "${NODE##*/}" ]
P1_SZ=$(lsblk -bdn -o SIZE "$PN"); [ "$P1_SZ" = 2147483648 ]
MOUNTS=$(lsblk -dn -o MOUNTPOINTS "$PN"); [ -z "$MOUNTS" ]
H=/sys/class/block/${PN##*/}/holders; [ -d "$H" ]
HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
mkfs.vfat -F 32 -n ESP "$P"
FSTYPE=$(blkid -s TYPE -o value "$P"); [ "$FSTYPE" = vfat ]
echo "ESP formatted and verified"
'
```

New LUKS2 container. **Native prompts are the last thing this child does** — type `YES`, then choose the NEW passphrase (twice). It becomes every manual boot's passphrase until/unless TPM enrollment happens later; keep it in your password manager or on paper — never in this vault. Nothing runs after the prompt returns.

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
TYPE=$(lsblk -dn -o TYPE "$NODE"); [ "$TYPE" = disk ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
P="$TARGET-part2"
PN=$(readlink -e "$P"); [ -b "$PN" ]
TYPE=$(lsblk -dn -o TYPE "$PN"); [ "$TYPE" = part ]
PARENT=$(lsblk -dn -o PKNAME "$PN"); [ "$PARENT" = "${NODE##*/}" ]
P2_SZ=$(lsblk -bdn -o SIZE "$PN"); [ "$P2_SZ" -gt 400000000000 ]
MOUNTS=$(lsblk -dn -o MOUNTPOINTS "$PN"); [ -z "$MOUNTS" ]
H=/sys/class/block/${PN##*/}/holders; [ -d "$H" ]
HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
if [ -e /dev/mapper/root ]; then echo "STOP: mapper root exists" >&2; exit 1; fi
cryptsetup luksFormat --type luks2 --pbkdf argon2id "$P"
'
```

Open it (same passphrase; prompt last in the child):

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
P="$TARGET-part2"
PN=$(readlink -e "$P"); [ -b "$PN" ]
TYPE=$(lsblk -dn -o TYPE "$PN"); [ "$TYPE" = part ]
PARENT=$(lsblk -dn -o PKNAME "$PN"); [ "$PARENT" = "${NODE##*/}" ]
MOUNTS=$(lsblk -dn -o MOUNTPOINTS "$PN"); [ -z "$MOUNTS" ]
H=/sys/class/block/${PN##*/}/holders; [ -d "$H" ]
HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
cryptsetup isLuks "$P"
if [ -e /dev/mapper/root ]; then echo "STOP: mapper root exists" >&2; exit 1; fi
cryptsetup open "$P" root
'
```

Prove the mapper backs exactly this partition, then create Btrfs **only if** the proof passes (canonical-path equality is the gate — not any displayed text):

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
[ -e /dev/mapper/root ]
MAP_DEV=$(cryptsetup status root | sed -n "s/^[[:space:]]*device:[[:space:]]*//p")
[ -n "$MAP_DEV" ]
[ -b "$MAP_DEV" ]
MAP_REAL=$(readlink -e "$MAP_DEV"); PART_REAL=$(readlink -e "$TARGET-part2")
[ -b "$MAP_REAL" ]; [ -b "$PART_REAL" ]; [ "$MAP_REAL" = "$PART_REAL" ]
PARENT=$(lsblk -dn -o PKNAME "$MAP_REAL"); [ "$PARENT" = "${NODE##*/}" ]
MAPPER=$(readlink -e /dev/mapper/root); [ -b "$MAPPER" ]
MOUNTS=$(lsblk -dn -o MOUNTPOINTS "$MAPPER"); [ -z "$MOUNTS" ]
H=/sys/class/block/${MAPPER##*/}/holders; [ -d "$H" ]
HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
# No -f: native mkfs.btrfs refuses an existing filesystem signature.
mkfs.btrfs -L ume-root /dev/mapper/root
FSTYPE=$(blkid -s TYPE -o value /dev/mapper/root); [ "$FSTYPE" = btrfs ]
echo "Btrfs created and verified"
'
```

## Phase 5 — Btrfs Subvolumes, Mounts, and Swap

Subvolumes and mounts (child `set -e`: a failed mount stops before further directory writes):

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
[ -d /mnt ]
[ ! -L /mnt ]
INV_TARGETS=$(findmnt -rn -o TARGET)
if [ -z "$INV_TARGETS" ]; then echo "STOP: findmnt inventory empty" >&2; exit 1; fi
while read -r MT; do [ "$MT" != /mnt ]; done <<< "$INV_TARGETS"
PROBE=$(find /mnt -mindepth 1 -printf x -quit)
if [ -n "$PROBE" ]; then echo "STOP: /mnt not empty" >&2; exit 1; fi
MAP_DEV=$(cryptsetup status root | sed -n "s/^[[:space:]]*device:[[:space:]]*//p")
MAP_REAL=$(readlink -e "$MAP_DEV"); PART_REAL=$(readlink -e "$TARGET-part2")
[ -b "$MAP_REAL" ]; [ -b "$PART_REAL" ]; [ "$MAP_REAL" = "$PART_REAL" ]
FSTYPE=$(blkid -s TYPE -o value /dev/mapper/root); [ "$FSTYPE" = btrfs ]
MAPPER=$(readlink -e /dev/mapper/root); [ -b "$MAPPER" ]
MOUNTS=$(lsblk -dn -o MOUNTPOINTS "$MAPPER"); [ -z "$MOUNTS" ]
H=/sys/class/block/${MAPPER##*/}/holders; [ -d "$H" ]
HOLDERS=$(ls -A "$H"); [ -z "$HOLDERS" ]
mount /dev/mapper/root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
umount /mnt
mount -o compress=zstd:3,subvol=@ /dev/mapper/root /mnt
mkdir -p /mnt/boot /mnt/home /mnt/var/log /mnt/swap
mount -o compress=zstd:3,subvol=@home /dev/mapper/root /mnt/home
mount -o compress=zstd:3,subvol=@log /dev/mapper/root /mnt/var/log
mount -o fmask=0077,dmask=0077 "$TARGET-part1" /mnt/boot
for SPEC in /mnt:@ /mnt/home:@home /mnt/var/log:@log; do
  MT=${SPEC%:*}; SUB=${SPEC##*:}
  SRC=$(findmnt --nofsroot -rn -M "$MT" -o SOURCE)
  SRC_REAL=$(readlink -e "$SRC"); [ -b "$SRC_REAL" ]; [ "$SRC_REAL" = "$MAPPER" ]
  FS=$(findmnt -rn -M "$MT" -o FSTYPE); [ "$FS" = btrfs ]
  OPTS=$(findmnt -rn -M "$MT" -o OPTIONS)
  case ",$OPTS," in *,subvol=/$SUB,*) ;; *) exit 1;; esac
done
SRC=$(findmnt --nofsroot -rn -M /mnt/boot -o SOURCE)
SRC_REAL=$(readlink -e "$SRC"); ESP_REAL=$(readlink -e "$TARGET-part1")
[ -b "$SRC_REAL" ]; [ "$SRC_REAL" = "$ESP_REAL" ]
FS=$(findmnt -rn -M /mnt/boot -o FSTYPE); [ "$FS" = vfat ]
echo "subvolumes mounted and verified"
'
```

Create the swapfile for real on the mounted new root, enable it at priority 0, verify it is active, and record the new identifiers (zram elsewhere is fine — no global-empty assertion):

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
MAP_DEV=$(cryptsetup status root | sed -n "s/^[[:space:]]*device:[[:space:]]*//p")
MAP_REAL=$(readlink -e "$MAP_DEV"); PART_REAL=$(readlink -e "$TARGET-part2")
[ -b "$MAP_REAL" ]; [ "$MAP_REAL" = "$PART_REAL" ]
MAPPER=$(readlink -e /dev/mapper/root); [ -b "$MAPPER" ]
SRC=$(findmnt --nofsroot -rn -M /mnt -o SOURCE)
SRC_REAL=$(readlink -e "$SRC"); [ -b "$SRC_REAL" ]; [ "$SRC_REAL" = "$MAPPER" ]
FS=$(findmnt -rn -M /mnt -o FSTYPE); [ "$FS" = btrfs ]
OPTS=$(findmnt -rn -M /mnt -o OPTIONS); case ",$OPTS," in *,subvol=/@,*) ;; *) exit 1;; esac
[ -d /mnt/swap ]
[ ! -L /mnt/swap ]
if [ -e /mnt/swap/swapfile ]; then echo "STOP: swapfile already exists" >&2; exit 1; fi
btrfs filesystem mkswapfile --size 32G /mnt/swap/swapfile
chmod 0600 /mnt/swap/swapfile
OFF=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
[ -n "$OFF" ]
swapon --priority 0 /mnt/swap/swapfile
swapon --show=NAME --noheadings | grep -qxF /mnt/swap/swapfile
printf "ESP UUID:   "; blkid -s UUID -o value "$TARGET-part1"
printf "LUKS UUID:  "; cryptsetup luksUUID "$TARGET-part2"
printf "Btrfs UUID: "; lsblk -dn -o UUID /dev/mapper/root
echo "swapfile active at priority 0 — record the UUIDs above"
'
```

## Phase 6 — Merge Machine Facts

Copy the checkout onto the target — fresh destination, expected mount, source revision proof. Never build from `/tmp`/ISO RAM:

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
CFG=${CFG:?export CFG first}
MODE=${MODE:?export MODE first}
[ -d "$CFG/.git" ]
[ -f "$CFG/flake.nix" ]
[ -f "$CFG/flake.lock" ]
case "$MODE" in
  git) HEAD_NOW=$(git -C "$CFG" rev-parse HEAD); [ "$HEAD_NOW" = "56ac7a6a7a23a373b5211cc2eb31d8d249fa74aa" ] ;;
  borg)
    cd "$CFG"
    printf "%s\n" \
    "da3c51b55f69ea3bbfdfbaca6581bac7a9063c616b816bda97f01bae5eb7f526  flake.lock" \
    "84318ec4a44d505575e9ac00731ca90541f592499b008b6693038da79bff4a81  INSTALL-UME.md" \
    "ffee6da5fd4424dfff4dad3aac5c66b521dfb82df6605955d4a1b382770a92e0  hosts/ume/default.nix" \
    "2f3ee47604a5197db1d67b54ebc55c3731405385cf3abc4e1983493eafaedd27  hosts/ume/hardware-configuration.nix" \
    "dd3d8d9198f925270f4a00ca7203225152e3753c31276e2892a769828b2a1180  home/features/editors.nix" \
    "2b36f51a4f7c3c04158a0bb38c3d5fe62d328b50d52348444890b0f9c5c62f6d  home/nvim/lua/plugins/plugins.lua" | sha256sum --check --status ;;
  *) echo "STOP: bad MODE" >&2; exit 1 ;;
esac
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
MAP_DEV=$(cryptsetup status root | sed -n "s/^[[:space:]]*device:[[:space:]]*//p")
MAP_REAL=$(readlink -e "$MAP_DEV"); PART_REAL=$(readlink -e "$TARGET-part2")
[ -b "$MAP_REAL" ]; [ "$MAP_REAL" = "$PART_REAL" ]
MAPPER=$(readlink -e /dev/mapper/root); [ -b "$MAPPER" ]
SRC=$(findmnt --nofsroot -rn -M /mnt -o SOURCE)
SRC_REAL=$(readlink -e "$SRC"); [ -b "$SRC_REAL" ]; [ "$SRC_REAL" = "$MAPPER" ]
FS=$(findmnt -rn -M /mnt -o FSTYPE); [ "$FS" = btrfs ]
OPTS=$(findmnt -rn -M /mnt -o OPTIONS); case ",$OPTS," in *,subvol=/@,*) ;; *) exit 1;; esac
[ ! -L /mnt/etc ]
[ ! -L /mnt/etc/nixos ]
DEST=/mnt/etc/nixos/kebun
if [ -e "$DEST" ] || [ -L "$DEST" ]; then echo "STOP: destination exists" >&2; exit 1; fi
mkdir -p /mnt/etc/nixos
PARENT_REAL=$(readlink -e /mnt/etc/nixos); [ "$PARENT_REAL" = /mnt/etc/nixos ]
cp -a "$CFG" "$DEST"
chown -R -P -h root:root "$DEST"    # ONLY this fresh destination; never follow symlinks
[ -f "$DEST/flake.nix" ]
[ -f "$DEST/flake.lock" ]
[ -f "$DEST/hosts/ume/hardware-configuration.nix" ]
echo "config copied and verified"
'
```

Generate a **reference-only** hardware readout, then merge by hand — never overwrite the flake blindly:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config > /tmp/ume-hardware.generated.nix
nano /tmp/ume-hardware.generated.nix   # reference; /tmp is RAM-only
nano /mnt/etc/nixos/kebun/hosts/ume/hardware-configuration.nix
nano /mnt/etc/nixos/kebun/hosts/ume/default.nix
```

UUID table — old values are the pre-install snapshot. **Actual post-install
values, verified against the live machine on 2026-10-15, are in the third
column and are now what `hosts/ume/` holds:**

| Item | Old (pre-install) | Actual, post-install |
|---|---|---|
| ESP `/boot` | `17FE-CA36` | **`12CE-A600`** (`/dev/nvme0n1p1`) |
| LUKS container (p2) | `fdfeaf01-6060-473f-9d01-dfd685d2e2fd` | **`af6c38b9-e330-47b5-97dd-da19a7f29a00`** (`/dev/nvme0n1p2`) |
| Btrfs root | `1ba0592d-…` | **`60691fd6-54bc-40ae-864a-c25e42a3307a`** — no device change: `/`, `/home`, `/var/log` stay on `/dev/mapper/root`; this is the inner-UUID comment only |
| Media ext4 | `5a56e7ae-9a37-49c2-9a98-728c5500a08d` | unchanged — keep exactly, even if detached |

**Commit this merge.** The step below says the edits stay uncommitted; that
is what stranded the corrected UUIDs outside the repo. Verify before
switching by diffing the built closure's fstab against the running one:

```bash
diff <(grep -v '^#' /run/current-system/etc/fstab | sort) \
     <(grep -v '^#' "$(nix build --no-link --print-out-paths \
        .#nixosConfigurations.ume.config.system.build.toplevel)/etc/fstab" | sort)
```

Merging rules:

- `hardware-configuration.nix`: update only the `/boot` device; `swapDevices = [{ device = "/swap/swapfile"; priority = 0; }]` (no `size`, no `resumeDevice`); keep the media automount; keep the initrd modules.
- `default.nix`: update the ONE existing `boot.initrd.luks.devices."root".device` to `/dev/disk/by-uuid/<new LUKS UUID>`; keep `crypttabExtraOpts` and `boot.initrd.systemd.enable`; there is no `allowDiscards` option in this source — do not add one; `stateVersion` stays `25.05`.
- Ignore generated entries for the installer USB, the ADATA drive, zram, or a duplicate root-LUKS block — there is exactly one LUKS declaration.
- Look at what changed; edits stay **uncommitted** by design:

For the **public Git clone only** (`MODE=git`), inspect `git status --short` and
`git diff --stat` in `/mnt/etc/nixos/kebun`. With `MODE=borg`, do not run Git
against restored metadata/configuration; review the two edited Nix files in nano.

`/mnt/etc/nixos/kebun` is the install-time copy only. It is **not** a durable
admin fallback — on this machine it did not survive the install, and because
the UUID merge above lived nowhere else, the corrected values were lost.
Treat it as scratch: the authority is the pushed Git remote (see Phase 9).

## Phase 7 — Install NixOS and Set the User Password

One install; it builds only ume into the target store (no separate ISO-RAM build). The final prompt is the **installed** system's root password — native, last; keep it (do not bypass it):

```bash
cd /mnt/etc/nixos/kebun
sudo nixos-install --root /mnt --no-write-lock-file --flake /mnt/etc/nixos/kebun#ume
```

Mandatory before the first reboot — `ivokun` ships locked (`initialHashedPassword = "!"`) and sudo requires a password. Native prompt, last:

```bash
sudo nixos-enter --root /mnt -c 'passwd ivokun'
```

Never run plain `passwd ivokun` in the live session — wrong system. The installer's bootloader may write EFI boot variables itself; that is expected.

## Phase 8 — Unmount and Reboot

`cd /` first (your cwd is under `/mnt`, which would busy-block unmounts). Verify backing, then close **only** the fresh root — explicit mounts, never `umount -R` (it could cross into media mounts):

```bash
cd /    # PARENT terminal must leave /mnt before launching the child below
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
[ "${TARGET:?export TARGET first}" = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2P36292DSGD7" ]
cd /
NODE=$(readlink -e "$TARGET"); [ -b "$NODE" ]
SERIAL=$(lsblk -dn -o SERIAL "$NODE"); [ "$SERIAL" = "2P36292DSGD7" ]
SIZE=$(lsblk -bdn -o SIZE "$NODE"); [ "$SIZE" = "512110190592" ]
MODEL=$(lsblk -dn -o MODEL "$NODE" | xargs); [ "$MODEL" = "XPG GAMMIX S70 BLADE" ]
grep -qx "ID=nixos" /etc/os-release; [ -d /sys/firmware/efi ]
ROOT_FS=$(findmnt -rn -o FSTYPE /); case "$ROOT_FS" in tmpfs|overlay) ;; *) exit 1;; esac
MAP_DEV=$(cryptsetup status root | sed -n "s/^[[:space:]]*device:[[:space:]]*//p")
MAP_REAL=$(readlink -e "$MAP_DEV"); PART_REAL=$(readlink -e "$TARGET-part2")
[ -b "$MAP_REAL" ]; [ "$MAP_REAL" = "$PART_REAL" ]
MAPPER=$(readlink -e /dev/mapper/root); [ -b "$MAPPER" ]
for SPEC in /mnt:@ /mnt/home:@home /mnt/var/log:@log; do
  MT=${SPEC%:*}; SUB=${SPEC##*:}
  SRC=$(findmnt --nofsroot -rn -M "$MT" -o SOURCE)
  SRC_REAL=$(readlink -e "$SRC"); [ -b "$SRC_REAL" ]; [ "$SRC_REAL" = "$MAPPER" ]
  FS=$(findmnt -rn -M "$MT" -o FSTYPE); [ "$FS" = btrfs ]
  OPTS=$(findmnt -rn -M "$MT" -o OPTIONS)
  case ",$OPTS," in *,subvol=/$SUB,*) ;; *) exit 1;; esac
done
SRC=$(findmnt --nofsroot -rn -M /mnt/boot -o SOURCE)
SRC_REAL=$(readlink -e "$SRC"); ESP_REAL=$(readlink -e "$TARGET-part1")
[ -b "$SRC_REAL" ]; [ "$SRC_REAL" = "$ESP_REAL" ]
FS=$(findmnt -rn -M /mnt/boot -o FSTYPE); [ "$FS" = vfat ]
swapon --show=NAME --noheadings | grep -qxF /mnt/swap/swapfile
swapoff /mnt/swap/swapfile
umount /mnt/boot
umount /mnt/home
umount /mnt/var/log
umount /mnt
cryptsetup close root
if [ -e /dev/mapper/root ]; then echo "STOP: mapper still present" >&2; exit 1; fi
echo "fresh mounts closed — safe to reboot"
'
```

Then reboot normally (normal flush; never a power-cut). Media/ADATA disks are not part of this cleanup; if mounted, handle them separately (safely unmount/eject).

## Phase 9 — First Boot Checks

- LUKS asks for the **manual passphrase** — expected; no TPM token exists yet (`tpm2-device=auto` does not enroll one).
- Log in at SDDM as `ivokun`, open a terminal, and start a bash session (`bash` — the login shell is fish); the checks below run there.

```bash
systemctl --failed
systemctl --user --failed
swapon --show        # expect zram (100% of RAM) priority 100 + /swap/swapfile priority 0
ls /mnt/entertainments    # trigger the declared automount first
findmnt -M /mnt/entertainments
sudo btrfs subvolume show /home/.snapshots   # sudo may prompt here; it is the last command
```

Quick desktop smoke: network (iwd/impala), audio, session lock, SUPER+K cheatsheet renders. Expected snapper limitation: the active swapfile inside `@` blocks **root** snapshots; `@home` snapshots are unaffected.

**User working copy (do this on ume, never on the editing machine).** The install checkout is root-owned with uncommitted UUID edits; `nh` as your user must not edit root files. Cache sudo first (native prompt alone), then copy — complete working copy including the uncommitted edits, root-ownership flipped to you, symlinks left physical:

```bash
sudo -v    # caches credentials for the copy; prompt alone in its own block
```

```bash
export WORK="$HOME/Documents/dev/kebun"
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
WORK=${WORK:?export WORK first}
ADMIN=/etc/nixos/kebun
[ "$WORK" = "$HOME/Documents/dev/kebun" ]
[ -d "$ADMIN" ]
ADMIN_REAL=$(readlink -e "$ADMIN"); [ "$ADMIN_REAL" = "$ADMIN" ]
[ ! -e "$WORK" ]
[ ! -L "$WORK" ]
sudo -n true
PARENT=${WORK%/*}
mkdir -p "$PARENT"
PARENT_REAL=$(readlink -e "$PARENT"); [ "$PARENT_REAL" = "$PARENT" ]
sudo -n cp -a "$ADMIN" "$WORK"
USER_NOW=$(id -un); GROUP_NOW=$(id -gn)
sudo -n chown -R -P -h "$USER_NOW:$GROUP_NOW" "$WORK"
[ -f "$WORK/flake.nix" ]
[ -f "$WORK/flake.lock" ]
echo "user working copy ready: $WORK"
'
```

From then on: edit/rebuild in `$WORK` (`cd "$WORK" && nix fmt && nh os switch .`) — pinned lock, no blanket flake update, no pull/reset of the hardware edits. If you later restore the old kebun source from the archive, do not let it overwrite the machine-facts edits.

**The pushed Git remote (`origin/main`) is the authority.** There is no
root-owned `/etc/nixos/kebun` fallback — the install-time copy is scratch and
was not preserved, which is exactly how the corrected UUIDs went missing.
That makes one rule load-bearing:

> **Machine-facts edits are not done until they are committed *and* pushed.**
> A UUID that exists only in the working copy is one reinstall away from
> being lost; a UUID that exists only locally is absent from the authority
> you would rebuild from. "Uncommitted by design" (Phase 6) applies to the
> install session only — commit and push as soon as the machine boots.

Recovering config on a fresh machine is then just `git clone`; nothing has to
be rescued out of `/etc`. The cost is that an unpushed commit is invisible to
recovery, so check `git status --short` and `git log --oneline origin/main..HEAD`
before you rely on the remote.

## Phase 10 — Restore Data Selectively

Run as your user (bash), **after** the first good boot. The source home alone is ≈ 333 GB (332,708,184,064 bytes allocated, 2026-10-05); headroom is unmeasured by design — check `df -h` and go incrementally, folder by folder, reusing one staging dir. Never extract the whole home, never copy through NTFS.

1. In your **nonroot Bash** terminal, obtain Borg first: `command -v borg`;
if missing, enter `nix-shell -p borgbackup` before assigning any variables.
Use Borg 1.4.x; native access must succeed. Stop on errors, never bypass locks.
Connect ADATA and mount it normally (GUI is fine); ordinary Borg locks need a
writable repository. Read-only mounting is not the routine procedure here.

```bash
lsblk -bpP -o NAME,TYPE,SIZE,MODEL,SERIAL,FSTYPE,UUID,MOUNTPOINTS
export ADATA_MNT=/run/media/ivokun/thumbdisk    # EDIT to the actual mounted directory
export REPO="$ADATA_MNT/kebun-pre-ume-20261012T105721Z-327b41a6/borg"
borg --version
```

2. Validate mounted partition UUID and its **physical parent disk** (partition
serial fields are commonly blank). No match means STOP, not an arbitrary path:

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
ADATA_MNT=${ADATA_MNT:?export actual mount directory}; REPO=${REPO:?export REPO}
SRC=$(findmnt --nofsroot -rn -M "$ADATA_MNT" -o SOURCE)
PART=$(readlink -e "$SRC"); [ -b "$PART" ]
UUID=$(lsblk -dn -o UUID "$PART"); [ "$UUID" = "083A183749A0AEE1" ]
TYPE=$(lsblk -dn -o TYPE "$PART"); [ "$TYPE" = part ]
PK=$(lsblk -dn -o PKNAME "$PART"); [ -n "$PK" ]
DISK=$(readlink -e "/dev/$PK"); [ -b "$DISK" ]
TYPE=$(lsblk -dn -o TYPE "$DISK"); [ "$TYPE" = disk ]
SERIAL=$(lsblk -dn -o SERIAL "$DISK"); [ "$SERIAL" = "2M37291155H1" ]
MODEL=$(lsblk -dn -o MODEL "$DISK" | xargs); [ "$MODEL" = "ADATA SX6000PNP" ]
SIZE=$(lsblk -bdn -o SIZE "$DISK"); [ "$SIZE" = 512110190592 ]
OPTS=$(findmnt -rn -M "$ADATA_MNT" -o OPTIONS); case ",$OPTS," in *,rw,*) ;; *) exit 1;; esac
[ "$REPO" = "$ADATA_MNT/kebun-pre-ume-20261012T105721Z-327b41a6/borg" ]; [ -d "$REPO" ]
echo "ADATA identity and mounted repository path OK"
'
```

3. Fresh private staging on a Linux filesystem (never NTFS), then list the folder you are about to restore — prompt last in the block (archive paths keep the `home/ivokun/…` prefix; guaranteed, not ambiguous):

```bash
umask 077
STAGING=$(mktemp -d "$HOME/restore-staging.XXXXXXXX")
export STAGING
RESTORE_PARENT="home/ivokun/Documents"    # bounded folder listing, not the entire archive
borg list --short "$REPO::home-and-saves-20261012T105721Z" "$RESTORE_PARENT"
```

Stop unless creation succeeded and the listing succeeded with actual matching
paths. Do not treat an empty listing as successful recovery. Keep the private
staging directory empty until extraction; listings are not written inside it.

4. Extract the chosen folder (prompt last; non-root; `cd` must succeed or the child stops):

```bash
export RESTORE_PATH="REPLACE_WITH_REAL_PATH"   # ← an exact path from the list step
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
STAGING=${STAGING:?export STAGING first}
REPO=${REPO:?export REPO first}
RESTORE_PATH=${RESTORE_PATH:?export RESTORE_PATH first}
case "$RESTORE_PATH" in home/ivokun/?*) ;; *) exit 1;; esac
case "/$RESTORE_PATH/" in */../*|*/./*|*//*|*\**|*\?*|*\[*|*PLACEHOLDER*|*REPLACE_*) exit 1;; esac
case "$RESTORE_PATH" in home/ivokun/.config/systemd*|home/ivokun/.config/hypr*|home/ivokun/.config/nvim*|home/ivokun/.config/alacritty*|home/ivokun/Documents/dev/kebun*|home/ivokun/.local/state/omarchy/current/theme*) exit 1;; esac
UID_NOW=$(id -u); [ "$UID_NOW" -ne 0 ]
[ -d "$STAGING" ]; [ ! -L "$STAGING" ]
CANON=$(readlink -e "$STAGING"); [ "$CANON" = "$STAGING" ]
MODE=$(stat -c %a "$STAGING"); [ "$MODE" = 700 ]
OWNER=$(stat -c %u "$STAGING"); [ "$OWNER" = "$UID_NOW" ]
FS=$(findmnt -rn -T "$STAGING" -o FSTYPE); case "$FS" in tmpfs|btrfs|ext4|xfs) ;; *) exit 1;; esac
ENTRIES=$(find "$STAGING" -mindepth 1 -maxdepth 1 -printf x -quit); [ -z "$ENTRIES" ]
[ -d "$REPO" ]
cd "$STAGING"
borg extract --show-rc "$REPO::home-and-saves-20261012T105721Z" "$RESTORE_PATH"
'
```

5. Immediately after extraction returns, run `printf "Extract exit: %s\n" "$?"`
alone. Require 0 and no warnings. The staged selected subtree must be a nonempty
directory, not a symlink. Choose an explicit **new, nonexistent** destination;
never merge/overwrite an existing folder automatically:

```bash
export DESTINATION="$HOME/Documents/REPLACE_WITH_NEW_FOLDER_NAME"
```

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc -c '
set -euo pipefail
STAGING=${STAGING:?}; RESTORE_PATH=${RESTORE_PATH:?}; DESTINATION=${DESTINATION:?}
case "$DESTINATION" in *REPLACE_*|*PLACEHOLDER*) exit 1;; esac
SOURCE="$STAGING/$RESTORE_PATH"
[ -d "$SOURCE" ]; [ ! -L "$SOURCE" ]
CANON=$(readlink -e "$SOURCE"); [ "$CANON" = "$SOURCE" ]
case "$CANON" in "$STAGING"/home/ivokun/?*) ;; *) exit 1;; esac
PRESENT=$(find "$SOURCE" -mindepth 1 -maxdepth 1 -printf x -quit); [ -n "$PRESENT" ]
case "$DESTINATION" in "$HOME"/Documents/?*|"$HOME"/Projects/?*|"$HOME"/Downloads/?*) ;; *) exit 1;; esac
[ ! -e "$DESTINATION" ]; [ ! -L "$DESTINATION" ]
PARENT=${DESTINATION%/*}; [ -d "$PARENT" ]
PARENT_REAL=$(readlink -e "$PARENT"); [ "$PARENT_REAL" = "$PARENT" ]
mv -T -n -- "$SOURCE" "$DESTINATION"
[ ! -e "$SOURCE" ]; [ -d "$DESTINATION" ]
echo "Selected folder moved without merging/overwriting"
'
```

Repeat per folder; delete consumed staging content to bound space. Do **not** restore: old Arch `~/.config/systemd/user/` units, Home-Manager-owned paths (Hyprland Lua, theme, alacritty/nvim configs, generated symlinks), `/etc/passwd`, `shadow`, `fstab`, `crypttab`, EFI/bootloader material, Tailscale identity, `/var/lib/docker`. Data already on the kept media SSD (games, libraries) needs no restore. Changes after 2026-10-12 may be missing. Ownership differences from a non-root restore are normal — do not chase UID equality. No new whole-data checks are needed: no `--verify-data`, no `--repair`, no lock bypass; the 2026-10-12 verification stands. When finished, safely unmount/eject the ADATA before any disconnect.

## Optional — TPM and LUKS Login Key Later

Only after the manual passphrase boot, SDDM login, and `sudo -v` have all **actually worked**, and you have rebooted at least once. (A header backup is also generally good practice before relying on restored data; it is never generated automatically and never stored in this vault.)

1. Before any key-slot or enrollment change, back up the **new** container's header: `cryptsetup luksHeaderBackup` to a root-only staging path (umask 077), verify with `luksDump` + SHA-256, store it **encrypted** off-site with a second copy on an independent physical medium — never in this vault, never plaintext on the NTFS drive. Delete the plaintext staging copy.
2. Enrollment commands and any `luksAddKey`/`systemd-cryptenroll` step wait for a new explicit go — this note deliberately contains no keyslot commands.
3. After every key/enrollment change: fresh header backup, then a second boot with the manual passphrase fallback still tested before treating TPM as primary.

PCR 7 TPM auto-unlock is convenience only; Secure Boot is not provisioned, so this is not verified boot.

## Recovery

- **No Arch fallthrough.** After Phase 3–4 the old system is gone; the old LUKS header is not a restore plan. Recovery data comes only from the Borg archive.
- **No earlier generation yet.** A fresh install has one generation, so `nixos-rebuild --rollback` has nothing to target until the next rebuild — and it never restores user data anyway.
- **Rescue path:** boot the HP USB → unlock the **new** container → mount `@`, `@home`, `@log`, and the ESP (**no `mkfs`**) → `nixos-enter --root /mnt` to inspect/repair.
- **Config recovery = `git clone` from `origin`,** not a copy out of `/etc`; there is no root-owned admin tree on this machine. Anything committed locally but never pushed is *not* recoverable this way — verify with `git log --oneline origin/main..HEAD` before trusting the remote.
- **A host that will not activate is usually a stale device UUID,** not a broken closure. `switch-to-configuration` unmounts `/boot` and remounts it; if `fileSystems."/boot"` names a device that does not exist, `local-fs.target` fails and the machine reaches emergency mode. Check `/dev/disk/by-uuid` against `hosts/<name>/` first.
- **Partial stage failure:** inspect what exists, take a fresh explicit go, resume from the matching phase — never re-run a failed destructive block blind.
- **Once data is restored, repair in place.** No re-wipe. Protect the backup and media disks.

## Operational Checklist

Checked = already true today; unchecked = pending.

- [x] Borg repo + data archive `home-and-saves-20261012T105721Z` — integrity/authentication check + representative restore passed (not a full-OS image)
- [x] Owner keeps archive key/passphrase physically; "encrypted key open" item superseded
- [x] Checkout archive `ume-checkout-20261014T001037Z` created; extract dry-run passed (config fallback only)
- [x] Kebun commit pushed: `56ac7a6a…` on `main`/`origin`
- [x] Installer/rescue USB (HP v210w, serial `000000000000003F`) boot-verified with the NixOS 26.05 installer
- [ ] Phase 1 live-state child OK (NixOS live/UEFI; target serial/size/model; unused; `/mnt` unmounted+empty)
- [ ] Phase 2 config source ready (`CFG`, `MODE` git HEAD 56 / fallback six file digests; no restored Git execution)
- [ ] Phase 3–5 writes gated and verified (GPT geometry; ESP; LUKS2; Btrfs; mounts; 32G swapfile priority 0)
- [ ] Phase 6 machine facts merged (new ESP + LUKS UUIDs; media UUID kept; no duplicates; uncommitted by design)
- [ ] Phase 7 `nixos-install` completed; `passwd ivokun` set via `nixos-enter` before reboot
- [ ] Phase 8 cleanup child OK; normal reboot (no power-cut)
- [ ] Phase 9 first boot: manual LUKS, SDDM login, `sudo -v`; `systemctl --failed` clean; `swapon` shows zram 100/100 + swapfile 0; media + `/home/.snapshots`
- [x] Phase 9 user working copy at `$HOME/Documents/dev/kebun` (ownership flipped)
- [ ] Machine-facts UUIDs committed **and pushed** to `origin/main` — the authority; no `/etc/nixos/kebun` fallback exists
- [ ] Phase 10 data restored selectively and incrementally (post-2026-10-12 gaps checked; ADATA ejected)
- [ ] Optional: header backup first, then TPM/login-key enrollment — with a new explicit go

## Primary Sources

- [INSTALL-UME.md (pinned)](https://github.com/ivokun/kebun/blob/56ac7a6a7a23a373b5211cc2eb31d8d249fa74aa/INSTALL-UME.md) — the authoritative runbook this note compresses
- [NixOS manual — installation](https://nixos.org/manual/nixos/stable/#sec-installation)
- [Btrfs documentation — filesystem mkswapfile](https://btrfs.readthedocs.io/en/latest/btrfs-filesystem.html)
- [systemd-cryptenroll(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html) — enrollment is explicit; `tpm2-device=auto` alone does nothing
- [sgdisk manual (Rod Smith)](https://www.rodsbooks.com/gdisk/sgdisk-walkthrough.html)
- [borg list (1.4)](https://borgbackup.readthedocs.io/en/stable/usage/list.html) — `--short` with a path gives a direct folder listing
