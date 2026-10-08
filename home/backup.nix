{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # Shared Borg backup excludes (used by every eventual kebun host — the old
  # home/sakura.nix).
  #
  # Migration note (Arch ivokun-htpc → NixOS ume): before pointing Borg at a
  # live home directory, review these patterns against what is actually on
  # disk and do a restore test of a sample archive. Excludes here have bitten
  # real backups before: the audit that produced this file found Git archives
  # silently missing .git/objects (unrestorable repos) and blanket patterns
  # eating save data (see comments inline).

  # ─── Borg backup excludes ───
  # Input for manual/off-host Borg runs only; no scheduled Borg job or secret
  # is declared here. Snapper's same-disk snapshots are not a backup.
  #
  # Deliberately NOT excluded (do not add these back):
  # ~/.git/** — full Git history, objects, refs and reflogs (a repo backup
  #   without .git/objects is not restorable);
  # ~/Downloads at any depth — user data, not disposable;
  # game data anywhere — saved games, configs, mods, workshop content,
  #   userdata and Proton prefixes. Steam's saves routinely live far from
  #   steamapps/common (e.g. ~/.steam/steam/userdata, Documents saves,
  #   prefixuserdata), and modified-installed-game files are not recoverable
  #   by re-downloading the pristine copy from the store.
  home.file.".borg-excludes".text = ''
    # Cache directories
    **/.cache
    **/Cache
    **/.cargo/registry
    **/.npm
    **/.yarn/cache
    **/node_modules
    **/__pycache__
    **/.pytest_cache

    # Browser caches
    **/.mozilla/firefox/*/cache2
    **/.config/google-chrome/*/Cache
    **/.config/chromium/*/Cache

    # Thumbnails and temporary files
    **/.thumbnails
    **/.local/share/Trash
    **/Trash
    **/.Trash
    *.tmp
    *.temp
    **/*~

    # Steam — narrow, layout-aware cache exclusions only. The old blanket
    # roots (.local/share/Steam, .steam) also swallowed userdata (saves),
    # Proton prefixes, workshop content and the package/appcache roots the
    # client itself rebuilds from; steamapps/common may be re-downloadable
    # in theory, but modified game files in it are not, so it is retained.
    # Only throwaway client cache/cache-adjacent dirs are excluded, matched
    # against the two layouts seen in the wild (~/.local/share/Steam and
    # ~/.steam/steam).
    **/.local/share/Steam/appcache
    **/.local/share/Steam/package
    **/.local/share/Steam/steamapps/shadercache
    **/.local/share/Steam/steamapps/downloading
    **/.local/share/Steam/logs
    **/.steam/steam/appcache
    **/.steam/steam/steamapps/shadercache
    **/.steam/steam/steamapps/downloading
    **/.steam/steam/package
    **/.steam/steam/logs

    # Downloads (user data — never exclude; see header note)

    # Development build artifacts
    **/target/debug
    **/target/release
    **/build
    **/dist
    **/.parcel-cache
    **/.next
    **/out
    # Note: **/.git/objects was here once and silently broke repo backups —
    # never re-add anything under **/.git.

    # Virtual environments
    **/venv
    **/.venv
    **/virtualenv
    **/.conda

    # Logs — per-file *.log removed (it ate app/project data); shell session
    # logs and app-logger output live scattered, so prefer explicit,
    # verifiably-log-only paths here over blanket matches.
    **/.config/obs-studio/logs
    **/.local/share/DaVinciResolve/logs

    # Video editing cache
    **/.local/share/DaVinciResolve/.cache
  '';
}
