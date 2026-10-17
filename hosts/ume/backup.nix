# ume's scheduled Borg backup (ADR-0018).
#
# Daily, catch-up (persistent timer) backup of /home/ivokun to a per-host
# repository on the TrueNAS export. The repo passphrase is a sops-nix secret
# decrypted at activation with ume's SSH host key (readable by ivokun only); it never enters the Nix
# store. The NAS is on-site, so this is not an off-site backup.
{
  config,
  pkgs,
  ...
}: {
  sops = {
    defaultSopsFile = ../../secrets/ume.yaml;
    # Default sshKeyPaths (the ed25519 host key) is the decryption identity.
    secrets.borg-passphrase.owner = "ivokun";
  };

  # Editing secrets/ume.yaml needs the sops CLI.
  environment.systemPackages = [pkgs.sops];

  services.borgbackup.jobs.home = {
    # Runs as ivokun so the borg cache and the secret stay user-owned; the
    # NAS maps all writes to its own uid either way.
    user = "ivokun";
    group = "users";
    paths = ["/home/ivokun"];
    repo = "/mnt/tubeinas/borgbackups/ume";
    # Not removable — this only suppresses the module's tmpfiles rule, which
    # would chown the repo dir to ivokun:users (1000:100) as root. The NAS
    # maps every client to its own uid 3000, so that chown locks the repo
    # against all writes. The dir was created once by hand, as ivokun; it
    # must exist before the unit starts (it is in ReadWritePaths).
    removableDevice = true;
    # repokey-blake2: the key lives in the repo, guarded by the passphrase.
    # Export it once after the first run (`borg key export`) into the
    # password manager — without key + passphrase the repo is unreadable.
    doInit = true;
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.sops.secrets.borg-passphrase.path}";
    };
    compression = "auto,zstd";
    # The HM-managed exclude list (home/backup.nix); review it before
    # trusting the first archive.
    extraCreateArgs = ["--exclude-from" "/home/ivokun/.borg-excludes" "--exclude-caches"];
    startAt = "daily";
    persistentTimer = true;
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
  };

  # The repo is on the NFS automount; mount it before borg starts.
  systemd.services.borgbackup-job-home.unitConfig.RequiresMountsFor = ["/mnt/tubeinas"];
}
