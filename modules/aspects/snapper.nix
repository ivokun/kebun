{
  hostUserNames,
  pkgs,
  ...
}: {
  services.snapper = {
    cleanupInterval = "1d";
    filters = ''
      # Exclude directories from pre/post snapshot comparisons
      - .cache
      - .local/share/Trash
      - node_modules
      - .git
    '';
  };

  # ─── Btrfs Snapshots (home only) — shared workstation policy ───
  services.snapper.configs = {
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = hostUserNames;
      # snapper(8) requires root ownership and no non-root write access.
      # Snapper grants the declared users read/traverse access through ACLs.
      SYNC_ACL = true;
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 10;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 12;
    };
  };

  # systemd-tmpfiles `v` is not sufficient here: it only creates a Btrfs
  # subvolume when `/` itself is a subvolume, and hosts differ on layout —
  # sakura mounts Btrfs's top level as `/`, ume uses an `@` subvol. Safely
  # migrate the empty regular directory that a tmpfiles `d` rule may have
  # left behind, but never delete contents. Snapper is held back if the path
  # is non-empty or otherwise unexpected.
  systemd.services.home-snapshots-subvolume = {
    description = "Provision the /home Snapper subvolume";
    wantedBy = ["multi-user.target"];
    requiredBy = [
      "snapperd.service"
      "snapper-timeline.service"
      "snapper-cleanup.service"
    ];
    before = [
      "snapperd.service"
      "snapper-timeline.service"
      "snapper-cleanup.service"
    ];
    unitConfig.RequiresMountsFor = "/home";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = let
      chown = "${pkgs.coreutils}/bin/chown";
      chmod = "${pkgs.coreutils}/bin/chmod";
      rmdir = "${pkgs.coreutils}/bin/rmdir";
      find = "${pkgs.findutils}/bin/find";
      btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
      owner = "root:users";
    in ''
      set -euo pipefail
      target=/home/.snapshots

      if ${btrfs} subvolume show "$target" >/dev/null 2>&1; then
        ${chown} ${owner} "$target"
        ${chmod} 0750 "$target"
        exit 0
      fi

      if [ -e "$target" ]; then
        if [ ! -d "$target" ] || [ -n "$(${find} "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
          echo "$target exists but is not an empty Btrfs subvolume; refusing to replace it" >&2
          exit 1
        fi
        ${rmdir} -- "$target"
      fi

      ${btrfs} subvolume create "$target"
      ${chown} ${owner} "$target"
      ${chmod} 0750 "$target"
    '';
  };
}
