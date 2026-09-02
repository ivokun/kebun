{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # Host-specific home-manager settings for sakura

  # ─── Hyprland monitor layout ───
  # Moved to ~/.config/hypr/monitors.lua (ADR-0007 Stage 3) — the Lua layer
  # replaced the HM-generated monitor list.

  # ─── Borg backup excludes ───
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

    # Development build directories
    **/target/debug
    **/target/release
    **/build
    **/dist
    **/.git/objects

    # Large media working directories
    **/.local/share/Steam
    **/.steam

    # Virtual environments
    **/venv
    **/.venv
    **/virtualenv

    # Logs
    *.log
    **/logs

    # Large media/games (re-downloadable)
    **/.local/share/Steam
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

    # Temporary files
    **/.thumbnails
    **/.local/share/Trash
    **/Trash
    **/.Trash
    *.tmp
    *.temp
    **/*~
    *.log
    **/logs

    # Video editing cache
    **/.local/share/DaVinciResolve/.cache
  '';

  # Wallpaper path (will be set after copying wallpaper)
  # xdg.configFile."omarchy/current/background".source = ../../wallpapers/sakura-bg.jpg;
}
