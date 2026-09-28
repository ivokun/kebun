{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # Shared Borg backup excludes (used by every eventual kebun host — the old
  # home/sakura.nix).

  # ─── Borg backup excludes ───
  # Input for manual/off-host Borg runs only; no scheduled Borg job or secret
  # is declared here. Snapper's same-disk snapshots are not a backup.
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

    # Large media/games (re-downloadable)
    **/.local/share/Steam
    **/.steam
    **/.steam/steam/steamapps/common
    **/.steam/steam/package
    **/.steam/steam/appcache
    **/.steam/steam/logs
    **/Games
    **/games

    # Downloads (optional - you decide)
    **/Downloads

    # Development build artifacts
    **/target/debug
    **/target/release
    **/build
    **/dist
    **/.git/objects
    **/.parcel-cache
    **/.next
    **/out

    # Virtual environments
    **/venv
    **/.venv
    **/virtualenv
    **/.conda

    # Logs
    *.log
    **/logs

    # Video editing cache
    **/.local/share/DaVinciResolve/.cache
  '';
}
