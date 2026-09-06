# ADR-0010: Unlock LUKS via TPM2 and Prompt Once at SDDM

## Status

Accepted

## Context

The original authentication flow on sakura had a contradiction:

- The user typed a password **on boot** — but that password was the LUKS
  passphrase, consumed by systemd-cryptsetup and never seen by PAM.
- SDDM was configured to **autologin** (`Autologin` in
  `hosts/common/desktop.nix`), so no login password ever reached PAM either.
- The keyring wiring was correct but starved: `pam_gnome_keyring.so` was
  configured on sddm/login (via `security.pam.services.*.enableGnomeKeyring`),
  yet with autologin the PAM auth phase never ran, so the keyring stayed
  locked and prompted on first use.
- `unlockLuksOnLogin` (a PAM exec that re-uses the login password to open
  LUKS) was equally inert.
- Because there are **two** LUKS containers (root `5525…` and the dedicated
  swap partition `e1906…`, kept out of shared modules per ADR-0001), the
  initrd queued two Plymouth passphrase prompts per boot, costing ~28 s of
  the 31.9 s initrd time.
- `hosts/sakura/default.nix` already declared
  `crypttabExtraOpts = ["tpm2-device=auto" "tpm2-measure-pcr=yes"]` on both
  volumes, but no TPM2 token had ever been enrolled — every boot logged
  `No valid TPM2 token data found` and fell back to the passphrase.

Upstream Omarchy reaches "one prompt" differently: a single LUKS container
with a swapfile inside (so only one device exists) plus a plaintext default
keyring with SDDM autologin — and it actively deletes `pam_gnome_keyring`
from sddm's PAM so no second keyring can appear. Matching that layout would
require destructive offline repartitioning and giving up the ADR-0001 swap
decision; the plaintext keyring trades real secret encryption for
convenience. Both were rejected.

## Decision

**Zero prompts at boot, exactly one at login.**

1. **Enroll TPM2** on both LUKS volumes (one-time, offline-safe):

   ```bash
   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
     /dev/disk/by-uuid/5525027e-a087-470e-a530-3ab692f4a14c
   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
     /dev/disk/by-uuid/e1906a9e-c934-4352-bfea-02620b6abd80
   ```

   PCR 7 only, deliberately: binding PCR 11 would re-lock the disk on every
   nixos-rebuild (new kernels measure differently). PCR 7 survives rebuilds
   and only demands the passphrase again if firmware/Secure Boot config
   shifts — at which point boot falls back to the passphrase prompt, exactly
   like the old behavior. The passphrase keyslots remain enrolled as
   fallback.

2. **Remove SDDM autologin** (`hosts/common/desktop.nix`). The single SDDM
   password becomes the machine's only prompt and unlocks the keyring
   through the already-wired `pam_gnome_keyring` hook.

3. **Keep `unlockLuksOnLogin`** as-is: with TPM2 the volumes are already
   open at login, so the helper no-ops; if TPM2 unlock ever fails at boot
   and the volumes arrive locked, the login password still opens them.

4. **Do not port upstream's plaintext keyring.** Secrets stay encrypted
   under the login password; the one-prompt goal is met without weakening
   the keyring.

## Consequences

### Positive

- Boot is silent: no Plymouth passphrase prompts at all; the initrd dropped
  from ~31.9 s to ~6.4 s measured
- Exactly one password per boot, at the greeter — and it unlocks the keyring
  (popup on first use is gone)
- Layout unchanged: ADR-0001's two-container split and shared-module hygiene
  survive; no offline repartitioning
- Graceful degradation: TPM refusal (firmware update moving PCR 7) falls
  back to the familiar passphrase prompt

### Negative

- Autologin is gone: every boot stops at the greeter (this is the point,
  but it is a behavior change)
- If the *Login* keyring's password ever diverges from the account password,
  one Seahorse password change is needed to restore silent unlock
- PCR 7 binding adds a small operational dependency: enroll again after
  firmware updates that shift Secure Boot policy

### Neutral

- Hibernation remains impossible (LUKS swap 8.8 GiB < 30.6 GiB RAM); the
  runbook comment in `hosts/sakura/default.nix` still describes the swap
  resize required to change that
- Upstream's single-LUKS layout remains documented as the alternative that
  would also enable hibernation, if the swap partition is ever rebuilt

## References

- ADR-0001 (LUKS layout), ADR-0002 (iwd), ADR-0006 (suspend path)
- Upstream: omacom/omarchy `install/login/sddm.sh`, `default-keyring.sh`,
  `install/login/hibernation.sh` (single-container reference model)
- `hosts/sakura/default.nix` (TPM2 crypttab options),
  `hosts/common/desktop.nix` (autologin removal, keyring PAM)

## Notes

- Date proposed: 2026-09-06
- Date accepted: 2026-09-06
- Proposed by: ivokun + agent session (boot-sequence audit)
- Accepted by: ivokun
