{
  pkgs,
  lib,
  ...
}: let
  browser = "google-chrome";

  # ─── Curated web apps (mirrors Omarchy's first-class PWA set) ───
  # Add or remove entries freely — desktop entries, the picker menu, and
  # focus-or-launch behavior are all generated from this one list.
  #
  # `match` is the substring used to focus an already-open window. Chromium's
  # `--app` mode derives the Wayland app_id as `chrome-<host>__-Default`, so
  # matching on the host is reliable regardless of the page title.
  webapps = [
    {
      name = "ChatGPT";
      url = "https://chatgpt.com";
      match = "chatgpt.com";
    }
    {
      name = "Claude";
      url = "https://claude.ai";
      match = "claude.ai";
    }
    {
      name = "HEY Email";
      url = "https://app.hey.com";
      match = "app.hey.com";
    }
    {
      name = "YouTube";
      url = "https://youtube.com";
      match = "youtube.com";
    }
    {
      name = "WhatsApp";
      url = "https://web.whatsapp.com";
      match = "web.whatsapp.com";
    }
    {
      name = "Google Messages";
      url = "https://messages.google.com/web/conversations";
      match = "messages.google.com";
    }
    {
      name = "Google Photos";
      url = "https://photos.google.com";
      match = "photos.google.com";
    }
    {
      name = "Google Maps";
      url = "https://maps.google.com";
      match = "maps.google.com";
    }
    {
      name = "X";
      url = "https://x.com";
      # Chromium --app app_id is `chrome-<host>__-Default`; the host substring
      # is the focus key (backlog §0.4 — "//x.com" never matched).
      match = "x.com";
    }
    {
      name = "GitHub";
      url = "https://github.com";
      match = "github.com";
    }
  ];

  slug = name: lib.toLower (builtins.replaceStrings [" "] ["-"] name);

  # Focus an existing window (match on app_id/title) or launch a fresh PWA.
  # `launch-or-focus` is provided by packages/scripts and is on the session PATH.
  launchCmd = app: "launch-or-focus ${lib.escapeShellArg app.match} ${browser} --app=${lib.escapeShellArg app.url}";

  menuArgs = lib.concatMapStringsSep " " (a: lib.escapeShellArg a.name) webapps;
  caseArms = lib.concatMapStringsSep "\n" (a: ''
    ${lib.escapeShellArg a.name}) exec ${launchCmd a} ;;'')
  webapps;

  menu-webapp = pkgs.writeShellScriptBin "menu-webapp" ''
    set -euo pipefail
    CHOICE=$(printf '%s\n' ${menuArgs} | omarchy-menu-select "Web app" || true)
    [ -z "$CHOICE" ] && exit 0
    case "$CHOICE" in
    ${caseArms}
    esac
  '';
in {
  home.packages = [menu-webapp];

  # Desktop entries — discoverable in the shell's app search and the app grid.
  xdg.desktopEntries = builtins.listToAttrs (map (app: {
      name = "webapp-${slug app.name}";
      value = {
        name = app.name;
        genericName = "Web App";
        exec = "${browser} --app=${app.url}";
        icon = "google-chrome";
        categories = ["Network" "X-WebApp"];
      };
    })
    webapps);
}
