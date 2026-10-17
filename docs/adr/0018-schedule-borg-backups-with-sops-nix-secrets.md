# ADR-0018: Schedule Borg Backups with sops-nix Secrets

- Status: Accepted
- Date: 2026-10-16
- Deciders: Ivokun
- Tags: backup, secrets, nixos, ume

## Context

Kebun has had no scheduled backup: `home/backup.nix` only writes an exclude
list for manual Borg runs, and Snapper is same-disk history. The Arch
ivokun-htpc's `borg-backup.timer` was failing (its last archive in
`tubeinas:/borgbackups/ivokun` dates from 2026-04-02) and was deliberately
not carried to ume (INSTALL-UME.md §4.1). The blocker was never Borg itself
but the secret: a timer needs the repo passphrase without a login session,
and kebun's rule is that no secret enters the repo in plaintext or the Nix
store (ADR-0014).

## Decision

1. **sops-nix for secrets.** Add `sops-nix` as a flake input. Secrets live
   encrypted in `secrets/<host>.yaml`; `.sops.yaml` lists the recipients.
   Each host decrypts at activation with its **SSH host ed25519 key**
   converted to age (sops-nix's default `sshKeyPaths`), so no new key
   material is provisioned on the host. A personal age key
   (`~/.config/sops/age/keys.txt`, never committed) is the second recipient
   so the secrets stay editable if a host key is lost.
2. **One repository per host** on the NAS: `borgbackups/ume`, matching the
   existing `borgbackups/clan/<host>` layout. The Arch-era `borgbackups/ivokun`
   repo stays untouched as history.
3. **ume job** (`hosts/ume/backup.nix`): `/home/ivokun`, the HM exclude list
   plus `--exclude-caches`, `repokey-blake2`, `auto,zstd`, daily with a
   persistent timer (catches up after the desktop was off), prune 7 daily /
   4 weekly / 6 monthly. Runs as ivokun; the unit requires the NFS
   automount.
4. **The NAS owns the repo directory.** The TrueNAS export maps every client
   write to its own uid 3000. The module's tmpfiles rule (root, `chown` to
   1000:100) locked the repo against all writes on the first run, so the job
   sets `removableDevice = true` purely to suppress that rule, and the repo
   directory is created once by hand as ivokun.

## Consequences

### Positive

- ume has an automatic, encrypted, deduplicated home backup.
- The secrets mechanism is reusable — sakura can adopt it by adding its host
  recipient and a job.

### Negative

- The NAS is on-site: a fire/theft takes machine and backup together. An
  off-site copy is still open.
- Re-keying a host (reinstall, new SSH host key) means `sops updatekeys`
  from a machine holding the personal age key before that host can
  activate.
- The repokey must be exported (`borg key export`) and stored with the
  passphrase in the password manager, or the repo is unrecoverable if its
  `config` is damaged.

### Neutral

- The job fails (does not silently skip) when the NAS is unreachable;
  check `systemctl status borgbackup-job-home`.

## References

- ADR-0014 — trust boundaries (no secrets in the store)
- INSTALL-UME.md §4.1 — the Borg keep/drop decision
- `home/backup.nix` — exclude list and its history
