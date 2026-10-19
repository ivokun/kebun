# Amp runner (ume)

ume runs a permanent [Amp runner](https://ampcode.com/docs/cli/runners): a
headless `amp --no-tui` instance serving ume's Git checkouts to threads
created from [ampcode.com](https://ampcode.com) — work on ume from the web
or phone.

## Design

- **Host-owned system service** (`systemd.services.amp-runner`, not a
  `--user` unit), defined in `hosts/ume/amp-runner.nix` and imported only
  by `hosts/ume/default.nix` — no Home Manager settings, capability
  option, or linger.
- Runs as `User=ivokun`/`Group=users`, standard `HOME`,
  `WorkingDirectory=/home/ivokun/Documents/dev`; tools resolve via an
  explicit store/profile `PATH` — shell env and `ssh-agent` not inherited.
- Exec: `amp --no-tui --runner-id ume --discover-dirs --no-serve-cwd
  --remote-control-terminal`.
  - `--discover-dirs` serves every Git checkout within two levels of the
    working directory and watches for new clones and worktrees.
  - `--no-serve-cwd` keeps the bare working directory out of the web
    location picker; only discovered checkouts are served.
  - `--remote-control-terminal` lets web threads open a terminal on ume.
  - No `--desktop`/`--share`, and no new inbound firewall ports.
- `Restart=always` every 30 s, retrying indefinitely — missing auth or
  being offline self-heals once the cause is fixed.
- Starts with `multi-user.target` — up at boot without a graphical login,
  survives logout, and does **not** prevent suspend: while ume sleeps the
  runner is unreachable, so leave it on when agents should work.

## Trust boundary

The runner is ivokun with ivokun's full access and no directory sandbox: a
thread on it can read and change anything that user can. Treat
ampcode.com access to this runner as ume shell access, including access
to SSH credentials. Protect your Amp account and signed-in devices accordingly.

## Auth

The service uses ume's ordinary Amp login state — the same account as
ampcode.com. Log in as ivokun on ume, **never** `sudo amp login`, and the
key never lives in this repo or the Nix store.

## First startup (once, on ume)

Build first and log in with the new CLI before enabling the service. This
avoids authentication failures during the first switch. While the new files
are not yet tracked, use an explicit path so the working tree is evaluated
as-is:

```bash
nix build path:.#nixosConfigurations.ume.config.system.build.toplevel
./result/sw/bin/amp login                    # as ivokun, never sudo
sudo nixos-rebuild switch --flake path:.#ume   # from this checkout, on ume
```

Once the files are tracked, the normal `nh os switch .` applies again.
The path-flake switch does not publish these changes to `origin/main`;
a separate commit and push are still needed for fresh-clone recovery.
For later account changes, run `amp login` and restart the service.

The runner now appears as **ume** in the location picker when creating a
thread on ampcode.com. Verify as shown in the next section.

## Operating commands (system-level)

```bash
systemctl status amp-runner                    # is it running
journalctl -u amp-runner -b --no-pager -n 50   # this boot's log
sudo systemctl restart amp-runner              # pick up login or config change
sudo systemctl stop amp-runner                 # stop until reboot/restart
```

## Changing the directory scope

The scope is `WorkingDirectory` plus the `--discover-dirs` root, both set
in `hosts/ume/amp-runner.nix`. To serve a different tree, edit that file,
rebuild on ume, and restart the service; within the scope, new clones and
worktrees are picked up automatically.

## Updating the CLI

The CLI is pinned to an official release (currently
`0.0.1792368068-g91990d`) in `packages/amp-cli/default.nix`, which reuses
nixpkgs' build logic and wrapper; the wrapper force-sets
`AMP_SKIP_UPDATE_CHECK=1`, so updates flow only through this repo. To bump:

1. Read the official version manifest:
   <https://static.ampcode.com/cli/cli-version.txt>
2. Update the version and the fixed source hash in
   `packages/amp-cli/default.nix` — do **not** run a blanket
   `nix flake update`.
3. Validate: the package builds, `amp --version` and `amp --help` work,
   and `nix build .#nixosConfigurations.ume.config.system.build.toplevel`
   succeeds; then switch on ume and `sudo systemctl restart amp-runner`.

## Sources

- [Runners](https://ampcode.com/docs/cli/runners) — flags, runner IDs, dirs
- [Settings](https://ampcode.com/docs/cli/settings) — runner env/secrets
