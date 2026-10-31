{
  pkgs,
  laptop ? false,
  # The compositor's own hyprctl (the flake input), not nixpkgs' pkgs.hyprland —
  # the two versions drift and a mismatched client misleads hyprctl-driven scripts.
  # Callers pass inputs.hyprland.packages.${system}.hyprland.
  hyprland ? pkgs.hyprland,
  ...
}: let
  palette = import ../../lib/palette.nix;
  hardwareMenu = builtins.concatStringsSep "\n" (
    [
      "Audio controls"
      "Bluetooth controls"
      "WiFi controls"
    ]
    ++ pkgs.lib.optional laptop "Battery status"
    ++ [
      "Power profile"
      "Brightness up"
      "Brightness down"
      "Volume up"
      "Volume down"
    ]
  );
  batteryMenuCase = pkgs.lib.optionalString laptop ''
    "Battery status") omarchy-notification-battery ;;
  '';
  # steam-repair-bootstrap: every external command is a store path, and the
  # bootstrap payload comes from the immutable archive in steam-unwrapped.
  steamCu = "${pkgs.coreutils}/bin";
  steamTar = "${pkgs.gnutar}/bin/tar";
  steamXz = "${pkgs.xz}/bin/xz";
  steamGrep = "${pkgs.gnugrep}/bin/grep";
  steamPgrep = "${pkgs.procps}/bin/pgrep";
  steamFlock = "${pkgs.util-linux}/bin/flock";
  steamFind = "${pkgs.findutils}/bin/find";
in {
  # Screenshot annotation editor, invoked as OMARCHY_SCREENSHOT_EDITOR by the
  # vendored omarchy-capture-screenshot. Upstream defaults to tensaku-edit,
  # which is unpackaged in nixpkgs; swappy preserves kebun's previous editor.
  # Must be a single-word executable: omarchy-notification-send --exec takes
  # argv verbatim, so "swappy -f" as the env value would not word-split.
  screenshot-edit = pkgs.writeShellScriptBin "screenshot-edit" ''
    exec ${pkgs.swappy}/bin/swappy -f "$@"
  '';

  # Bring the panel back after resume, and *prove* that it came back.
  #
  # The previous version asserted `hyprctl dispatch dpms on` == "ok". That test
  # is vacuous: Actions::dpms skips every monitor with !m_enabled and then
  # returns a default-constructed success, so "ok" is printed even when every
  # output is disabled — and even for a monitor name that does not exist. That
  # false positive is why the last three attempts at this bug concluded "the
  # panel was lit" and went hunting for a wedged hyprlock instead.
  #
  # The real failure: a `keyword monitor eDP-1,disable` queued by the lid
  # handler destroys the only wl_output. With zero enabled outputs Hyprland is
  # in unsafe state, and CMonitorFrameScheduler::canRender() refuses to render,
  # so monitor rules never drain from the render pre-check hook —
  # `keyword monitor …,preferred,auto,1` answers "ok" and changes nothing.
  # Only `hyprctl reload` recovers, because CConfigManager::reload calls
  # ensureMonitorStatus() directly, and it also drops the runtime disable.
  #
  # And it has to keep watching, not check once. Freezing user.slice defers the
  # lid handler's disable until resume: measured landing 273 ms *after* hypridle
  # had already run this script. Pass a settle window in seconds to keep
  # re-checking (the resume hook does); no argument means check once and return,
  # which is what the idle listener wants so `&& brightnessctl -r` is not held up.
  wake-display = pkgs.writeShellScriptBin "wake-display" ''
    set -uo pipefail

    hc=${hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    # Outputs the compositor will actually render on. HEADLESS is excluded: it
    # satisfies a naive count without lighting up any physical panel.
    enabled_outputs() {
      n=$("$hc" monitors -j 2>/dev/null |
        "$jq" -r '[.[] | select(.disabled == false) | select((.name | startswith("HEADLESS")) | not)] | length' 2>/dev/null) || n=""
      case "$n" in
        "" | *[!0-9]*) echo 0 ;;
        *) echo "$n" ;;
      esac
    }

    # Not a health check — see above. Just the thing that undoes the 605s
    # idle listener's `dpms off`.
    "$hc" dispatch dpms on >/dev/null 2>&1 || true

    settle=''${1:-0}
    ticks=$((settle * 2))
    tick=0

    while :; do
      if [ "$(enabled_outputs)" -eq 0 ]; then
        echo "no enabled output; hyprctl reload to restore monitor state" >&2
        "$hc" reload >/dev/null 2>&1 || true
        ${pkgs.coreutils}/bin/sleep 1
        "$hc" dispatch dpms on >/dev/null 2>&1 || true
        if [ "$(enabled_outputs)" -eq 0 ]; then
          echo "reload did not restore an output; the display is still dark." >&2
        fi
      fi

      [ "$tick" -ge "$ticks" ] && break
      tick=$((tick + 1))
      ${pkgs.coreutils}/bin/sleep 0.5
    done
  '';

  # Color picker
  color-picker = pkgs.writeShellScriptBin "color-picker" ''
    ${pkgs.procps}/bin/pkill hyprpicker || ${pkgs.hyprpicker}/bin/hyprpicker -a
  '';

  # Window pop (float + pin active window)
  window-pop = pkgs.writeShellScriptBin "window-pop" ''
    ${hyprland}/bin/hyprctl dispatch togglefloating
    ${hyprland}/bin/hyprctl dispatch pin
    ${hyprland}/bin/hyprctl dispatch centerwindow
  '';

  # Check for flake updates (interactive)
  check-updates = pkgs.writeShellScriptBin "check-updates" ''
    echo "Checking flake inputs for updates..."
    cd ~/Documents/dev/kebun
    ${pkgs.nix}/bin/nix flake metadata --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '
      .locks.nodes.root.inputs[] as $input |
      .locks.nodes[$input] |
      select(.locked) |
      "\($input): \(.locked.rev // .locked.version // "unknown")"
    '
    echo ""
    echo "To update: nix flake update"
  '';

  # Battery remaining time estimate
  battery-remaining-time = pkgs.writeShellScriptBin "battery-remaining-time" ''
    set -euo pipefail
    NOW=/sys/class/power_supply/BAT0/energy_now
    PWR=/sys/class/power_supply/BAT0/power_now
    if [ -f "$NOW" ] && [ -f "$PWR" ]; then
      N=$(${pkgs.coreutils}/bin/cat "$NOW")
      P=$(${pkgs.coreutils}/bin/cat "$PWR")
      if [ "$P" -gt 0 ] 2>/dev/null; then
        MINUTES=$(echo "scale=0; ($N * 60) / $P" | ${pkgs.bc}/bin/bc)
        HOURS=$(echo "scale=1; $MINUTES / 60" | ${pkgs.bc}/bin/bc)
        echo "$HOURS hours"
      else
        echo "Charging"
      fi
    else
      echo "N/A"
    fi
  '';

  # Toggle window gaps
  toggle-gaps = pkgs.writeShellScriptBin "toggle-gaps" ''
    set -euo pipefail
    STATE_FILE="$XDG_RUNTIME_DIR/hypr-gaps-state"
    if [ -f "$STATE_FILE" ]; then
      ${hyprland}/bin/hyprctl keyword general:gaps_in 5
      ${hyprland}/bin/hyprctl keyword general:gaps_out 10
      rm -f "$STATE_FILE"
      omarchy-notification-send "Gaps" "Normal spacing"
    else
      ${hyprland}/bin/hyprctl keyword general:gaps_in 0
      ${hyprland}/bin/hyprctl keyword general:gaps_out 0
      touch "$STATE_FILE"
      omarchy-notification-send "Gaps" "No gaps"
    fi
  '';

  # Toggle layout (dwindle/master)
  toggle-layout = pkgs.writeShellScriptBin "toggle-layout" ''
    set -euo pipefail
    CURRENT=$(${hyprland}/bin/hyprctl getoption general:layout | ${pkgs.gawk}/bin/awk -F '= ' '{print $2}')
    if [ "$CURRENT" = "dwindle" ]; then
      ${hyprland}/bin/hyprctl keyword general:layout master
      omarchy-notification-send "Layout" "Master layout"
    else
      ${hyprland}/bin/hyprctl keyword general:layout dwindle
      omarchy-notification-send "Layout" "Dwindle layout"
    fi
  '';

  # Toggle power profile
  toggle-power-profile = pkgs.writeShellScriptBin "toggle-power-profile" ''
    set -euo pipefail
    if ! CURRENT=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null); then
      omarchy-notification-send -u critical "Power Profile" "Failed to read current profile"
      exit 1
    fi
    if [ "$CURRENT" = "power-saver" ]; then
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced
      omarchy-notification-send "Power Profile" "Balanced"
    elif [ "$CURRENT" = "balanced" ]; then
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
      omarchy-notification-send "Power Profile" "Performance"
    else
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
      omarchy-notification-send "Power Profile" "Power Saver"
    fi
  '';

  # ─── TUI Launch System (inspired by Omarchy) ───
  # Smart focus-or-launch for TUI applications.
  # Prevents duplicate windows: if a window with the given class/title exists,
  # focus it; otherwise launch the command in a new session.
  launch-or-focus = pkgs.writeShellScriptBin "launch-or-focus" ''
    set -euo pipefail
    WINDOW_PATTERN="$1"
    shift

    WINDOW_ADDRESS=$(${hyprland}/bin/hyprctl clients -j | \
      ${pkgs.jq}/bin/jq -r --arg p "$WINDOW_PATTERN" '
      .[] | select((.class | ascii_downcase | contains($p | ascii_downcase))
      or (.title | ascii_downcase | contains($p | ascii_downcase))) | .address' | \
      ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$WINDOW_ADDRESS" ]; then
      ${hyprland}/bin/hyprctl dispatch focuswindow "address:$WINDOW_ADDRESS"
    else
      exec uwsm app -- "$@"
    fi
  '';

  # Launch a TUI application in a terminal with a unique class.
  # Hyprland matches the class to apply floating/center/size rules.
  launch-tui = pkgs.writeShellScriptBin "launch-tui" ''
    APP_ID="org.kebun.$(${pkgs.coreutils}/bin/basename "$1")"
    exec uwsm app -- ${pkgs.alacritty}/bin/alacritty --class "$APP_ID" -e "$1" "''${@:2}"
  '';

  # Launch or focus wiremix (audio mixer TUI)
  launch-audio = pkgs.writeShellScriptBin "launch-audio" ''
    exec launch-or-focus "org.kebun.wiremix" ${pkgs.alacritty}/bin/alacritty --class org.kebun.wiremix -e wiremix
  '';

  # Launch or focus impala (Wi-Fi TUI)
  launch-wifi = pkgs.writeShellScriptBin "launch-wifi" ''
    exec launch-or-focus "org.kebun.impala" ${pkgs.alacritty}/bin/alacritty --class org.kebun.impala -e impala
  '';

  # Launch or focus bluetui (Bluetooth TUI)
  launch-bluetooth = pkgs.writeShellScriptBin "launch-bluetooth" ''
    exec launch-or-focus "org.kebun.bluetui" ${pkgs.alacritty}/bin/alacritty --class org.kebun.bluetui -e bluetui
  '';

  # Launch or focus btop (system activity TUI)
  launch-activity = pkgs.writeShellScriptBin "launch-activity" ''
    exec launch-or-focus "org.kebun.btop" ${pkgs.alacritty}/bin/alacritty --class org.kebun.btop -e btop
  '';

  # ─── Toggle Menu ───
  menu-toggle = pkgs.writeShellScriptBin "menu-toggle" ''
    set -euo pipefail

    CHOICE=$(echo -e "Window transparency\nWindow gaps\nSingle-window square\nNightlight\nIdle locking\nLayout (dwindle/master)\nTop bar" | \
      omarchy-menu-select "Toggle")

    case "$CHOICE" in
      "Window transparency")
        ${hyprland}/bin/hyprctl dispatch setprop "address:$(${hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.address')" opaque toggle
        ;;
      "Window gaps") toggle-gaps ;;
      "Single-window square") toggle-single-window-square ;;
      "Nightlight") omarchy-toggle-nightlight ;;
      "Idle locking") omarchy-toggle-idle ;;
      "Layout (dwindle/master)") toggle-layout ;;
      "Top bar") omarchy-toggle-bar ;;
    esac
  '';

  # ─── Hardware Menu ───
  menu-hardware = pkgs.writeShellScriptBin "menu-hardware" ''
    set -euo pipefail

    CHOICE=$(printf '%s\n' ${pkgs.lib.escapeShellArg hardwareMenu} | \
      omarchy-menu-select "Hardware")

    case "$CHOICE" in
      "Audio controls") uwsm app -- ${pkgs.pavucontrol}/bin/pavucontrol ;;
      "Bluetooth controls") uwsm app -- ${pkgs.blueman}/bin/blueman-manager ;;
      "WiFi controls") launch-wifi ;;
      ${batteryMenuCase}
      "Power profile") toggle-power-profile ;;
      "Brightness up") omarchy-brightness-display +5% ;;
      "Brightness down") omarchy-brightness-display 5%- ;;
      "Volume up") omarchy-audio-output-volume raise ;;
      "Volume down") omarchy-audio-output-volume lower ;;
    esac
  '';

  # ─── Kebun Menu ───
  menu-omarchy = pkgs.writeShellScriptBin "menu-omarchy" ''
    set -euo pipefail

    CHOICE=$(echo -e "Terminal\nBrowser\nEditor\nFile manager\nLock screen\nActivity monitor\nKeybindings" | \
      omarchy-menu-select "Kebun")

    case "$CHOICE" in
      "Terminal") uwsm app -- ${pkgs.alacritty}/bin/alacritty ;;
      "Browser") uwsm app -- ${pkgs.google-chrome}/bin/google-chrome ;;
      "Editor") uwsm app -- ${pkgs.alacritty}/bin/alacritty -e ${pkgs.neovim}/bin/nvim ;;
      "File manager") uwsm app -- ${pkgs.nautilus}/bin/nautilus --new-window ;;
      "Lock screen") omarchy-system-lock ;;
      "Activity monitor") uwsm app -- ${pkgs.alacritty}/bin/alacritty -e btop ;;
      "Keybindings") omarchy-menu-keybindings ;;
    esac
  '';

  # ─── Background Menu ───
  menu-background = pkgs.writeShellScriptBin "menu-background" ''
    set -euo pipefail

    CHOICE=$(echo -e "Rose Pine Dawn\nSolid white\nSolid black\nSolid gray" | \
      omarchy-menu-select "Background")

    case "$CHOICE" in
      "Rose Pine Dawn") COLOR='${palette.background}' ;;
      "Solid white") COLOR='#ffffff' ;;
      "Solid black") COLOR='#000000' ;;
      "Solid gray") COLOR='#808080' ;;
      *) exit 0 ;;
    esac

    # Exactly one wallpaper process owns the outputs. Run the replacement in
    # the UWSM application scope so it remains part of the graphical session.
    ${pkgs.procps}/bin/pkill -x swaybg 2>/dev/null || true
    exec uwsm app -- ${pkgs.swaybg}/bin/swaybg -c "$COLOR" -m solid_color
  '';

  # ─── Close All Windows ───
  close-all-windows = pkgs.writeShellScriptBin "close-all-windows" ''
    set -euo pipefail
    mapfile -t ADDRESSES < <(${hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -r '.[].address')
    for addr in "''${ADDRESSES[@]}"; do
      ${hyprland}/bin/hyprctl dispatch closewindow "address:$addr" || true
    done
  '';

  # ─── Cycle Monitors ───
  cycle-monitors = pkgs.writeShellScriptBin "cycle-monitors" ''
    set -euo pipefail
    CURRENT=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .id')
    TOTAL=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq 'length')
    NEXT=$(( (CURRENT + 1) % TOTAL ))
    ${hyprland}/bin/hyprctl dispatch focusmonitor "$NEXT"
  '';

  # ─── Cycle Monitor Scaling ───
  cycle-monitor-scaling = pkgs.writeShellScriptBin "cycle-monitor-scaling" ''
    set -euo pipefail
    MONITOR=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
    CURRENT=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .scale')
    CURRENT=$(printf "%.2f" "$CURRENT")

    if [ "$CURRENT" = "1.00" ]; then
      NEXT="1.25"
    elif [ "$CURRENT" = "1.25" ]; then
      NEXT="1.50"
    elif [ "$CURRENT" = "1.50" ]; then
      NEXT="2.00"
    else
      NEXT="1.00"
    fi

    ${hyprland}/bin/hyprctl keyword monitor "$MONITOR,preferred,auto,$NEXT"
    omarchy-notification-send "Monitor Scale" "$MONITOR → $NEXT"
  '';

  # ─── File Manager (current directory) ───
  file-manager-cwd = pkgs.writeShellScriptBin "file-manager-cwd" ''
    set -euo pipefail
    CWD=$("${hyprland}/bin/hyprctl" activewindow -j | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')
    [ -z "$CWD" ] && CWD="$HOME"
    [ ! -d "$CWD" ] && CWD="$HOME"
    uwsm app -- ${pkgs.nautilus}/bin/nautilus --new-window "$CWD"
  '';

  # ─── Toggle Single-Window Square ───
  toggle-single-window-square = pkgs.writeShellScriptBin "toggle-single-window-square" ''
    set -euo pipefail
    STATE_FILE="$XDG_RUNTIME_DIR/hypr-square-state"
    if [ -f "$STATE_FILE" ]; then
      ${hyprland}/bin/hyprctl keyword general:gaps_in 5
      ${hyprland}/bin/hyprctl keyword general:gaps_out 10
      ${hyprland}/bin/hyprctl keyword general:border_size 2
      rm -f "$STATE_FILE"
      omarchy-notification-send "Layout" "Normal mode"
    else
      ${hyprland}/bin/hyprctl keyword general:gaps_in 0
      ${hyprland}/bin/hyprctl keyword general:gaps_out 0
      ${hyprland}/bin/hyprctl keyword general:border_size 0
      touch "$STATE_FILE"
      omarchy-notification-send "Layout" "Single-window square"
    fi
  '';

  # ─── Toggle Laptop Display ───
  # Toggle the internal panel, with the two invariants the old version lacked.
  # This script is where the post-suspend hang was manufactured.
  #
  # 1. Discovery uses `hyprctl monitors all -j`, not `hyprctl monitors -j`.
  #    A *disabled* monitor is absent from `monitors` altogether, so the old
  #    script looked up an empty INTERNAL and hit `exit 1` before ever reaching
  #    the re-enable: the panel it had just switched off could not be switched
  #    back on, by the lid handler or by SUPER+CTRL+DELETE. A one-way latch.
  #
  # 2. It refuses to disable the last enabled output. `keyword monitor
  #    NAME,disable` destroys the wl_output global; with none left Hyprland
  #    enters unsafe state, where nothing renders at all, ext-session-lock is
  #    granted to a surfaceless client that can never be evicted (the
  #    NOACTIVEMONS branch sends `locked` and returns *before* arming the 5s
  #    watchdog), and monitor rules stop draining so even `keyword monitor
  #    …,preferred` becomes a no-op. Recovery is a hard power-off.
  #
  # The guard is what makes the lid binding safe rather than merely lucky: it is
  # re-evaluated in the same process immediately before the disable, so a
  # handler frozen 100 ms into a suspend and thawed 20 hours later on resume
  # acts on live state and degrades to a no-op, instead of acting on a premise
  # that expired overnight. Ordering between the lid-close and lid-open
  # handlers stops mattering, which is what the previous fixes could not
  # arrange — suspend can invert it.
  #
  # HEADLESS outputs do not count: they would satisfy the guard without
  # lighting up a physical panel.
  toggle-laptop-display = pkgs.writeShellScriptBin "toggle-laptop-display" ''
    set -uo pipefail

    hc=${hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    INTERNAL=$("$hc" monitors all -j |
      "$jq" -r '.[] | select(.name | test("eDP|LVDS")) | .name' |
      ${pkgs.coreutils}/bin/head -1)

    if [ -z "$INTERNAL" ]; then
      omarchy-notification-send "Display" "No internal display found"
      exit 1
    fi

    DISABLED=$("$hc" monitors all -j |
      "$jq" -r --arg name "$INTERNAL" '.[] | select(.name == $name) | .disabled')

    # Fails safe: an unparseable count reads as 0 and so refuses the disable.
    enabled_outputs() {
      n=$("$hc" monitors -j 2>/dev/null |
        "$jq" -r '[.[] | select(.disabled == false) | select((.name | startswith("HEADLESS")) | not)] | length' 2>/dev/null) || n=""
      case "$n" in
        "" | *[!0-9]*) echo 0 ;;
        *) echo "$n" ;;
      esac
    }

    enable_internal() {
      # Re-applying a rule to a live output tears its wl_output global down and
      # re-advertises it — the exact path of the one real hyprlock SIGSEGV on
      # this machine (CRenderer::removeWidgetsFor via the registry global_remove
      # handler). So do nothing when it is already on.
      if [ "$DISABLED" != "true" ]; then
        exit 0
      fi
      "$hc" keyword monitor "$INTERNAL,preferred,auto,1"
      omarchy-notification-send "Display" "Internal monitor enabled"
    }

    disable_internal() {
      if [ "$DISABLED" = "true" ]; then
        exit 0
      fi
      if [ "$(enabled_outputs)" -le 1 ]; then
        echo "refusing to disable $INTERNAL: it is the only enabled output" >&2
        omarchy-notification-send "Display" "Keeping $INTERNAL on — it is the only display"
        exit 0
      fi
      "$hc" keyword monitor "$INTERNAL,disable"
      omarchy-notification-send "Display" "Internal monitor disabled"
    }

    case "''${1:-}" in
      on) enable_internal ;;
      off) disable_internal ;;
      *)
        if [ "$DISABLED" = "true" ]; then
          enable_internal
        else
          disable_internal
        fi
        ;;
    esac
  '';

  # ─── Lid Close ───
  # Lid-close handler for the Hyprland switch binding: lock, then panel off.
  # Locking happens here and not in logind because the shell's lock plugin
  # does not listen to logind's Lock()/LockedHint — HandleLidSwitch*=lock
  # would be a no-op. Same division of labour as upstream's
  # omarchy-system-lid-close.
  #
  # Docked (more than one enabled physical output) means clamshell mode is in
  # use on the external display — logind agrees (lidSwitchDocked = "ignore") —
  # so skip the lock and just park the internal panel. An unreadable probe
  # counts as undocked: a spurious lock is cheap, a missed one is not.
  #
  # On battery, logind suspends right after this runs (lidSwitch = "suspend"),
  # so the lock also lands ahead of sleep in practice — but with no delay
  # inhibitor there is no guarantee. The guaranteed variant is the sleep-lock
  # inhibitor service (parity backlog §3).
  lid-close = pkgs.writeShellScriptBin "lid-close" ''
    set -uo pipefail

    hc=${hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    enabled=$("$hc" monitors -j 2>/dev/null |
      "$jq" -r '[.[] | select(.disabled == false) | select((.name | startswith("HEADLESS")) | not)] | length' 2>/dev/null) || enabled=""

    docked=false
    case "$enabled" in
      "" | *[!0-9]*) ;; # probe failed → treat as undocked (lock)
      *) [ "$enabled" -ge 2 ] && docked=true ;;
    esac

    if [ "$docked" = false ]; then
      omarchy-system-lock >/dev/null 2>&1 || true
    fi

    toggle-laptop-display off
  '';

  # ─── Toggle Mirror Display ───
  toggle-mirror-display = pkgs.writeShellScriptBin "toggle-mirror-display" ''
    set -euo pipefail
    MONITORS=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[].name')
    COUNT=$(echo "$MONITORS" | ${pkgs.coreutils}/bin/wc -l)

    if [ "$COUNT" -lt 2 ]; then
      omarchy-notification-send "Display" "Only one monitor connected"
      exit 0
    fi

    PRIMARY=$(echo "$MONITORS" | ${pkgs.coreutils}/bin/head -1)
    SECONDARY=$(echo "$MONITORS" | ${pkgs.coreutils}/bin/tail -1)

    CURRENT_MIRROR=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg sec "$SECONDARY" '.[] | select(.name == $sec) | .mirrorOf // empty')
    if [ -n "$CURRENT_MIRROR" ]; then
      ${hyprland}/bin/hyprctl keyword monitor "$SECONDARY,preferred,auto,1"
      omarchy-notification-send "Display" "Mirroring disabled"
    else
      ${hyprland}/bin/hyprctl keyword monitor "$SECONDARY,preferred,auto,1,mirror,$PRIMARY"
      omarchy-notification-send "Display" "Mirroring $PRIMARY to $SECONDARY"
    fi
  '';

  # ─── LocalSend Share ───
  localsend-share = pkgs.writeShellScriptBin "localsend-share" ''
    set -euo pipefail
    uwsm app -- ${pkgs.localsend}/bin/localsend
  '';

  # ─── Show Battery ───
  show-battery = pkgs.writeShellScriptBin "show-battery" ''
    set -euo pipefail
    CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "N/A")
    STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    TIME=$(battery-remaining-time 2>/dev/null || echo "N/A")
    omarchy-notification-send "Battery" "$CAP% ($STATUS)\nRemaining: $TIME"
  '';

  # ─── Show Time ───
  show-time = pkgs.writeShellScriptBin "show-time" ''
    set -euo pipefail
    TIME=$(${pkgs.coreutils}/bin/date "+%I:%M %p")
    DATE=$(${pkgs.coreutils}/bin/date "+%A, %B %d, %Y")
    omarchy-notification-send "Time" "$TIME\n$DATE"
  '';

  # ─── Show Weather ───
  show-weather = pkgs.writeShellScriptBin "show-weather" ''
    set -euo pipefail
    LOCATION=$(${pkgs.curl}/bin/curl --max-time 5 --connect-timeout 5 -s "https://ipapi.co/json/" | ${pkgs.jq}/bin/jq -r '.city // "Tokyo"')
    WEATHER=$(${pkgs.curl}/bin/curl --max-time 5 --connect-timeout 5 -s "https://wttr.in/$LOCATION?format=%C+%t+%w" 2>/dev/null || echo "Unable to fetch weather")
    omarchy-notification-send "Weather in $LOCATION" "$WEATHER"
  '';

  # ─── Reminders ───
  reminder-set = pkgs.writeShellScriptBin "reminder-set" ''
    set -euo pipefail
    REMINDER_FILE="$XDG_DATA_HOME/kebun-reminders.txt"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$REMINDER_FILE")"

    INPUT=$(omarchy-menu-input "Reminder" </dev/null 2>/dev/null || true)
    [ -z "$INPUT" ] && exit 0

    echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M')] $INPUT" >> "$REMINDER_FILE"
    omarchy-notification-send "Reminder Set" "$INPUT"
  '';

  reminder-show = pkgs.writeShellScriptBin "reminder-show" ''
    set -euo pipefail
    REMINDER_FILE="$XDG_DATA_HOME/kebun-reminders.txt"
    if [ ! -f "$REMINDER_FILE" ] || [ ! -s "$REMINDER_FILE" ]; then
      omarchy-notification-send "Reminders" "No reminders set"
      exit 0
    fi

    CONTENT=$(${pkgs.coreutils}/bin/tail -20 "$REMINDER_FILE")
    omarchy-notification-send "Reminders" "$CONTENT"
  '';

  reminder-clear = pkgs.writeShellScriptBin "reminder-clear" ''
    set -euo pipefail
    REMINDER_FILE="$XDG_DATA_HOME/kebun-reminders.txt"
    [ -f "$REMINDER_FILE" ] && ${pkgs.coreutils}/bin/rm -f "$REMINDER_FILE"
    omarchy-notification-send "Reminders" "All reminders cleared"
  '';

  # ─── Dictation ───
  dictation-toggle = pkgs.writeShellScriptBin "dictation-toggle" ''
    set -euo pipefail
    if [ -x ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs ]; then
      ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs record toggle
      omarchy-notification-send "Dictation" "Toggled recording"
    else
      omarchy-notification-send "Dictation" "hyprwhspr-rs not installed"
    fi
  '';

  dictation-ptt = pkgs.writeShellScriptBin "dictation-ptt" ''
    set -euo pipefail
    if [ -x ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs ]; then
      ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs record start
    else
      omarchy-notification-send "Dictation" "hyprwhspr-rs not installed"
    fi
  '';

  dictation-ptt-release = pkgs.writeShellScriptBin "dictation-ptt-release" ''
    set -euo pipefail
    if [ -x ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs ]; then
      ${pkgs.hyprwhspr-rs}/bin/hyprwhspr-rs record stop
    fi
  '';

  # ─── Transcode ───
  transcode = pkgs.writeShellScriptBin "transcode" ''
    set -euo pipefail

    CHOICE=$(${pkgs.coreutils}/bin/echo -e "Compress video\nExtract audio\nConvert to MP4\nConvert to WebM" | \
      omarchy-menu-select "Transcode")

    # Use active window's working directory or home
    CWD=$("${hyprland}/bin/hyprctl" activewindow -j | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')
    [ -z "$CWD" ] && CWD="$HOME"
    cd "$CWD"

    case "$CHOICE" in
      "Compress video")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select video" || true)
        [ -z "$FILE" ] && exit 0
        OUTPUT="''${FILE%.*}-compressed.mp4"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -vcodec libx264 -crf 23 -preset fast "$OUTPUT"
        omarchy-notification-send "Transcode" "Compressed: $OUTPUT"
        ;;
      "Extract audio")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select video" || true)
        [ -z "$FILE" ] && exit 0
        OUTPUT="''${FILE%.*}.mp3"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -vn -acodec libmp3lame -q:a 2 "$OUTPUT"
        omarchy-notification-send "Transcode" "Audio extracted: $OUTPUT"
        ;;
      "Convert to MP4")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select file" || true)
        [ -z "$FILE" ] && exit 0
        OUTPUT="''${FILE%.*}.mp4"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -c:v libx264 -c:a aac "$OUTPUT"
        omarchy-notification-send "Transcode" "Converted: $OUTPUT"
        ;;
      "Convert to WebM")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select file" || true)
        [ -z "$FILE" ] && exit 0
        OUTPUT="''${FILE%.*}.webm"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -c:v libvpx-vp9 -c:a libopus "$OUTPUT"
        omarchy-notification-send "Transcode" "Converted: $OUTPUT"
        ;;
    esac
  '';

  # ─── Cursor Zoom ───
  cursor-zoom = pkgs.writeShellScriptBin "cursor-zoom" ''
    set -euo pipefail
    if ! ${pkgs.procps}/bin/pgrep -x hyprmag > /dev/null; then
      uwsm app -- ${pkgs.hyprmag}/bin/hyprmag
      omarchy-notification-send "Cursor Zoom" "Magnifier enabled"
    else
      omarchy-notification-send "Cursor Zoom" "Magnifier already running"
    fi
  '';

  cursor-zoom-reset = pkgs.writeShellScriptBin "cursor-zoom-reset" ''
    set -euo pipefail
    if ${pkgs.procps}/bin/pgrep -x hyprmag > /dev/null; then
      ${pkgs.procps}/bin/pkill -x hyprmag
      omarchy-notification-send "Cursor Zoom" "Magnifier disabled"
    fi
  '';

  # ─── Steam Bootstrap Repair ───
  # Steam skips bootstrap installation when steam.sh exists. A partial restore
  # can retain that script without its payload, causing runtime-unpack error 1
  # before the updater can repair it (the disk-space warning is misleading).
  # Restores only the two bootstrap directories the native Steam client needs
  # (ubuntu12_32/, linux32/) from the immutable archive shipped by the pinned
  # steam-unwrapped package. It never deletes existing Steam data, merges,
  # overwrites, restores top-level files, or launches Steam. An existing target
  # missing its structural markers is refused. Read-only by default; --apply is explicit.
  steam-repair-bootstrap = pkgs.writeShellScriptBin "steam-repair-bootstrap" ''
    set -euo pipefail

    ARCHIVE="${pkgs.steam-unwrapped}/lib/steam/bootstraplinux_ubuntu12_32.tar.xz"
    CU="${steamCu}"
    TAR="${steamTar}"
    XZ="${steamXz}"
    GREP="${steamGrep}"
    PGREP="${steamPgrep}"
    FLOCK="${steamFlock}"
    FIND="${steamFind}"

    say() { printf '%s\n' "$*"; }
    err() { printf 'steam-repair-bootstrap: %s\n' "$*" >&2; }

    usage() {
      "$CU/cat" <<'EOF'
    steam-repair-bootstrap - restore Steam's bootstrap runtime (ubuntu12_32, linux32)

    Usage:
      steam-repair-bootstrap [--check]   Read-only structural check (default)
      steam-repair-bootstrap --apply     Add absent ubuntu12_32/ and linux32/ only
      steam-repair-bootstrap --self-test Test recovery against private fixtures
      steam-repair-bootstrap --help      Show this help

    Check exit codes:
      0  structurally healthy
      1  bootstrap directories missing and safe to repair
      2  unsafe/invalid root or target, or Steam running (repair refused)

    --apply exits 0 on success or when already healthy. It never deletes
    existing Steam data, merges, overwrites, or launches Steam. Stop Steam before
    applying. The lock only serializes repair invocations; it cannot stop Steam starting.
    EOF
    }

    detect_root() {
      local link resolved
      link="$HOME/.steam/steam"
      if [ -L "$link" ]; then
        if ! resolved=$("$CU/readlink" -e -- "$link" 2>/dev/null); then
          err "Steam root link is dangling; inspect it before repairing: $link"
          return 2
        fi
        printf '%s\n' "$resolved"
        return 0
      fi
      printf '%s\n' "''${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
    }

    guard_root() {
      local root=$1
      if [ "$("$CU/id" -u)" -eq 0 ]; then err "refusing to run as root"; return 2; fi
      case "$root" in
        /|""|"$HOME") err "refusing unsafe root path: $root"; return 2 ;;
        /*) ;;
        *) err "Steam root path is not absolute: $root"; return 2 ;;
      esac
      if [ ! -d "$root" ] || [ -L "$root" ]; then err "Steam root is not a directory: $root"; return 2; fi
      if [ ! -O "$root" ]; then err "Steam root is not owned by the current user: $root"; return 2; fi
      if [ ! -w "$root" ]; then err "Steam root is not writable by the current user: $root"; return 2; fi
      if [ ! -f "$root/steam.sh" ] || [ -L "$root/steam.sh" ] || [ ! -x "$root/steam.sh" ]; then
        err "not a bootstrapped native Steam root (missing executable steam.sh): $root"
        return 2
      fi
      return 0
    }

    ubuntu_ok() {
      local d=$1
      [ -d "$d" ] && [ ! -L "$d" ] &&
        [ -f "$d/steam" ] && [ ! -L "$d/steam" ] && [ -x "$d/steam" ] &&
        [ ! -L "$d/steam-runtime" ] &&
        [ -f "$d/steam-runtime/setup.sh" ] && [ ! -L "$d/steam-runtime/setup.sh" ]
    }

    linux_ok() {
      local d=$1
      [ -d "$d" ] && [ ! -L "$d" ] &&
        [ -f "$d/steamerrorreporter" ] && [ ! -L "$d/steamerrorreporter" ] &&
        [ -x "$d/steamerrorreporter" ]
    }

    scan_targets() {
      local p
      ROOT_STATE_UBUNTU=absent
      ROOT_STATE_LINUX=absent
      UNSAFE=""
      MISSING=""

      p="$root/ubuntu12_32"
      if [ -L "$p" ]; then
        UNSAFE="$UNSAFE ubuntu12_32 is a symlink;"
      elif [ -e "$p" ]; then
        if [ -d "$p" ]; then
          if ubuntu_ok "$p"; then
            ROOT_STATE_UBUNTU=present
          else
            ROOT_STATE_UBUNTU=incomplete
            UNSAFE="$UNSAFE ubuntu12_32 is incomplete (needs steam and steam-runtime/setup.sh);"
          fi
        else
          UNSAFE="$UNSAFE ubuntu12_32 is not a directory;"
        fi
      else
        MISSING="$MISSING ubuntu12_32"
      fi

      p="$root/linux32"
      if [ -L "$p" ]; then
        UNSAFE="$UNSAFE linux32 is a symlink;"
      elif [ -e "$p" ]; then
        if [ -d "$p" ]; then
          if linux_ok "$p"; then
            ROOT_STATE_LINUX=present
          else
            ROOT_STATE_LINUX=incomplete
            UNSAFE="$UNSAFE linux32 is incomplete (needs steamerrorreporter);"
          fi
        else
          UNSAFE="$UNSAFE linux32 is not a directory;"
        fi
      else
        MISSING="$MISSING linux32"
      fi
    }

    report_state() {
      say "Steam root: $root"
      say "  ubuntu12_32: $ROOT_STATE_UBUNTU"
      say "  linux32:     $ROOT_STATE_LINUX"
      if [ -n "$UNSAFE" ]; then say "Unsafe:$UNSAFE"; fi
      if [ -n "$MISSING" ]; then say "Missing:$MISSING"; fi
    }

    pid_is_steam() {
      local pid=$1 comm
      [ -d "/proc/$pid" ] || return 1
      comm=$("$CU/cat" "/proc/$pid/comm" 2>/dev/null) || return 1
      case "$comm" in steam|steamwebhelper|steam.sh) return 0 ;; esac
      return 1
    }

    process_guard() {
      local uid name pid f found=""
      uid=$("$CU/id" -u)
      for name in steam steamwebhelper steam.sh; do
        pid=$("$PGREP" -u "$uid" -x "$name" 2>/dev/null || true)
        if [ -n "$pid" ]; then found="$found $name"; fi
      done
      for f in "$HOME/.steam/steam.pid" "$root/steam.pid"; do
        if [ ! -f "$f" ] || [ -L "$f" ]; then continue; fi
        pid=$("$CU/cat" -- "$f" 2>/dev/null || true)
        case "$pid" in ""|0*|*[!0-9]*) continue ;; esac
        if [ "''${#pid}" -gt 9 ]; then continue; fi
        if [ "$pid" -lt 2 ]; then continue; fi
        if [ -d "/proc/$pid" ] && [ "$("$CU/stat" -c %u "/proc/$pid" 2>/dev/null || echo x)" = "$uid" ] && pid_is_steam "$pid"; then
          found="$found pidfile:$f(pid $pid)"
        fi
      done
      if [ -n "$found" ]; then
        err "Steam is running:$found"
        err "exit Steam, then retry --apply"
        return 1
      fi
      return 0
    }

    acquire_lock() {
      if ! exec 9<"$root"; then err "cannot open Steam root for locking"; return 2; fi
      if ! "$FLOCK" -n 9; then
        exec 9<&-
        err "another repair invocation is already running for this root"
        return 2
      fi
      return 0
    }

    release_lock() { exec 9<&-; }

    stage=""
    cleanup_stage() {
      if [ -n "$stage" ] && [ -d "$stage" ] && [ ! -L "$stage" ]; then
        case "$stage" in */.steam-repair.*) "$CU/rm" -rf -- "$stage" ;; esac
      fi
      stage=""
    }

    validate_archive() {
      local archive=$1 list req
      if [ ! -x "$TAR" ] || [ ! -x "$XZ" ]; then err "tar/xz unavailable"; return 2; fi
      if [ ! -f "$archive" ] || [ -L "$archive" ] || [ ! -r "$archive" ]; then
        err "bootstrap archive is not a readable regular file: $archive"
        return 2
      fi
      if ! list=$("$TAR" --use-compress-program="$XZ" --list --file="$archive" 2>/dev/null); then
        err "bootstrap archive failed xz/tar validation"
        return 2
      fi
      if "$GREP" -Eq '(^/|(^|/)\.\.(/|$))' <<< "$list"; then
        err "bootstrap archive contains unsafe paths"
        return 2
      fi
      for req in ubuntu12_32/steam ubuntu12_32/steam-runtime/setup.sh linux32/steamerrorreporter; do
        if ! "$GREP" -Fqx -- "$req" <<< "$list"; then
          err "bootstrap archive is missing $req"
          return 2
        fi
      done
      return 0
    }

    validate_staged() {
      if ! ubuntu_ok "$stage/ubuntu12_32"; then
        err "staged ubuntu12_32 payload is incomplete or unsafe"
        return 1
      fi
      if ! linux_ok "$stage/linux32"; then
        err "staged linux32 payload is incomplete or unsafe"
        return 1
      fi
      return 0
    }

    stage_payload() {
      local root=$1 archive=$2
      stage=$("$CU/mktemp" -d "$root/.steam-repair.XXXXXXXX") || {
        stage=""
        err "cannot create staging directory under Steam root"
        return 1
      }
      "$CU/chmod" 700 "$stage" || { cleanup_stage; return 1; }
      if ! (
        umask 077
        "$TAR" --use-compress-program="$XZ" --extract --file="$archive" --directory="$stage" \
          --no-same-owner --no-same-permissions -- ubuntu12_32 linux32
      ); then
        err "failed to extract pinned bootstrap archive"
        cleanup_stage
        return 1
      fi
      return 0
    }

    do_check() {
      root=$1
      local skip=''${2:-0}
      guard_root "$root" || return 2
      scan_targets
      report_state
      if [ -n "$UNSAFE" ]; then err "unsafe/invalid target; no repair attempted"; return 2; fi
      if [ -z "$MISSING" ]; then say "Result: healthy"; return 0; fi
      if [ "$skip" -ne 1 ] && ! process_guard; then
        err "bootstrap directories are missing, but Steam is running (exit 2)"
        return 2
      fi
      say "Result: recoverable (run --apply)"
      return 1
    }

    do_apply() {
      root=$1
      local archive=$2 skip=''${3:-0}
      local entry missing
      guard_root "$root" || return 2
      scan_targets
      report_state
      if [ -n "$UNSAFE" ]; then
        err "unsafe/invalid target; refusing to merge, overwrite, or delete"
        return 2
      fi
      if [ -z "$MISSING" ]; then say "Result: healthy; nothing to do"; return 0; fi
      if [ "$skip" -ne 1 ] && ! process_guard; then return 2; fi

      acquire_lock || return 2

      if ! validate_archive "$archive"; then release_lock; return 2; fi
      if ! stage_payload "$root" "$archive"; then release_lock; return 1; fi
      if ! validate_staged; then cleanup_stage; release_lock; return 1; fi

      # Recheck guards and absence after extraction, immediately before writes.
      if [ "$skip" -ne 1 ] && ! process_guard; then cleanup_stage; release_lock; return 2; fi
      scan_targets
      if [ -n "$UNSAFE" ]; then
        cleanup_stage
        release_lock
        err "target changed during repair; refusing to write"
        return 2
      fi
      missing=$MISSING
      if [ -z "$missing" ]; then
        cleanup_stage
        release_lock
        say "Result: healthy; nothing to do"
        return 0
      fi

      # shellcheck disable=SC2086
      for entry in $missing; do
        if [ -e "$root/$entry" ] || [ -L "$root/$entry" ]; then
          err "$entry appeared during repair; refusing to overwrite"
          cleanup_stage
          release_lock
          return 2
        fi
        if [ ! -d "$stage/$entry" ] || [ -L "$stage/$entry" ]; then
          err "staged $entry is missing or unsafe"
          cleanup_stage
          release_lock
          return 1
        fi
        if ! "$CU/mv" -T -n -- "$stage/$entry" "$root/$entry"; then
          err "failed to move $entry into place"
          cleanup_stage
          release_lock
          return 1
        fi
        if [ ! -d "$root/$entry" ] || [ -L "$root/$entry" ] || [ -e "$stage/$entry" ] || [ -L "$stage/$entry" ]; then
          err "move verification failed for $entry (possible silent skip)"
          cleanup_stage
          release_lock
          return 1
        fi
        say "Restored $entry"
      done

      cleanup_stage
      release_lock

      if ubuntu_ok "$root/ubuntu12_32" && linux_ok "$root/linux32"; then
        say "Result: repaired. Start Steam when ready."
        return 0
      fi
      err "post-repair verification failed"
      return 1
    }

    ST_FAIL=0
    st_pass() { say "ok - $1"; }
    st_fail() { err "not ok - $1"; ST_FAIL=$((ST_FAIL + 1)); }
    expect_rc() {
      local want=$1 got=$2 name=$3
      if [ "$got" -eq "$want" ]; then st_pass "$name"; else st_fail "$name (expected $want, got $got)"; fi
    }
    expect_eq() {
      if [ "$1" = "$2" ]; then st_pass "$3"; else st_fail "$3"; fi
    }
    capture() {
      local rc
      set +e
      "$@" >/dev/null 2>&1
      rc=$?
      set -e
      printf '%s\n' "$rc"
    }

    make_root() {
      local r=$1
      "$CU/mkdir" -p "$r/config" "$r/steamapps/common" "$r/userdata/1/remote"
      printf '#!/bin/sh\nexit 0\n' > "$r/steam.sh"
      "$CU/chmod" 755 "$r/steam.sh"
      printf 'config\n' > "$r/config/config.vdf"
      printf 'app\n' > "$r/steamapps/common/sentinel.txt"
      printf 'save\n' > "$r/userdata/1/remote/sentinel.sav"
    }

    make_archive() {
      local out=$1 src=$2
      "$CU/mkdir" -p "$src/ubuntu12_32/steam-runtime" "$src/linux32"
      printf '#!/bin/sh\nexit 0\n' > "$src/ubuntu12_32/steam"
      printf '#!/bin/sh\nexit 0\n' > "$src/ubuntu12_32/steam-runtime/setup.sh"
      printf '#!/bin/sh\nexit 0\n' > "$src/linux32/steamerrorreporter"
      printf '#!/bin/sh\nexit 0\n' > "$src/steam.sh"
      "$CU/chmod" 755 "$src/ubuntu12_32/steam" "$src/ubuntu12_32/steam-runtime/setup.sh" \
        "$src/linux32/steamerrorreporter" "$src/steam.sh"
      "$TAR" --use-compress-program="$XZ" -c -f "$out" -C "$src" ubuntu12_32 linux32 steam.sh
    }

    tree_snapshot() {
      "$FIND" "$1" -mindepth 1 -printf '%P|%y|%s|%T@\n' | "$CU/sort"
    }

    sentinels() {
      "$CU/sha256sum" "$1/steam.sh" "$1/config/config.vdf" "$1/steamapps/common/sentinel.txt" \
        "$1/userdata/1/remote/sentinel.sav"
    }

    self_test() {
      local base root rc before
      base=$("$CU/mktemp" -d "''${TMPDIR:-/tmp}/steam-repair-selftest.XXXXXXXX") || {
        err "cannot create self-test fixture"
        return 1
      }
      TEST_BASE=$base
      HOME="$base/home"
      XDG_DATA_HOME="$HOME/.local/share"
      export HOME XDG_DATA_HOME
      "$CU/mkdir" -p "$HOME"

      make_archive "$base/good.tar.xz" "$base/src"
      "$CU/head" -c 64 "$base/good.tar.xz" > "$base/corrupt.tar.xz"

      # 1. Both directories missing; apply; check healthy; rerun is a no-op.
      root="$base/case1"
      make_root "$root"
      before=$(sentinels "$root")
      rc=$(capture do_check "$root" 1)
      expect_rc 1 "$rc" "check: both bootstrap dirs missing"
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 0 "$rc" "apply: restores both dirs"
      if ubuntu_ok "$root/ubuntu12_32" && linux_ok "$root/linux32"; then
        st_pass "apply: payload markers valid"
      else
        st_fail "apply: payload markers valid"
      fi
      rc=$(capture do_check "$root" 1)
      expect_rc 0 "$rc" "check: healthy after apply"
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 0 "$rc" "apply: repeated run is a no-op"
      expect_eq "$before" "$(sentinels "$root")" "protected steam.sh/config/steamapps/userdata unchanged"
      if [ -z "$("$FIND" "$root" -maxdepth 1 -name '.steam-repair.*' -print -quit)" ]; then
        st_pass "apply: staging cleaned up"
      else
        st_fail "apply: staging cleaned up"
      fi

      # 2. One directory absent, the other intact and untouched.
      root="$base/case2"
      make_root "$root"
      "$CU/cp" -a "$base/src/linux32" "$root/linux32"
      before=$(tree_snapshot "$root/linux32")
      rc=$(capture do_check "$root" 1)
      expect_rc 1 "$rc" "check: single dir missing"
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 0 "$rc" "apply: restores only the absent dir"
      expect_eq "$before" "$(tree_snapshot "$root/linux32")" "apply: existing linux32 unchanged"

      # 3. Corrupt archive is rejected before any change.
      root="$base/case3"
      make_root "$root"
      before=$(tree_snapshot "$root")
      rc=$(capture do_apply "$root" "$base/corrupt.tar.xz" 1)
      expect_rc 2 "$rc" "apply: corrupt archive rejected"
      expect_eq "$before" "$(tree_snapshot "$root")" "corrupt archive: root unchanged"
      if [ ! -e "$root/ubuntu12_32" ] && [ ! -e "$root/linux32" ]; then
        st_pass "corrupt archive: no target created"
      else
        st_fail "corrupt archive: no target created"
      fi

      # 4. Existing partial target is refused, not merged.
      root="$base/case4"
      make_root "$root"
      "$CU/mkdir" "$root/ubuntu12_32"
      printf 'junk\n' > "$root/ubuntu12_32/junk"
      before=$(tree_snapshot "$root")
      rc=$(capture do_check "$root" 1)
      expect_rc 2 "$rc" "check: partial target is unsafe"
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 2 "$rc" "apply: partial target refused"
      expect_eq "$before" "$(tree_snapshot "$root")" "partial target: unchanged"
      if [ ! -e "$root/linux32" ]; then st_pass "partial target: no sibling written"; else st_fail "partial target: no sibling written"; fi

      # 5. Symlink targets, live and dangling, are refused.
      root="$base/case5"
      make_root "$root"
      "$CU/mkdir" "$base/outside"
      printf 'keep\n' > "$base/outside/sentinel"
      "$CU/ln" -s "$base/outside" "$root/ubuntu12_32"
      before=$(tree_snapshot "$base/outside")
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 2 "$rc" "apply: symlink target refused"
      expect_eq "$before" "$(tree_snapshot "$base/outside")" "symlink target: link destination unchanged"
      if [ -L "$root/ubuntu12_32" ] && [ ! -e "$root/linux32" ]; then
        st_pass "symlink target: link kept, no sibling written"
      else
        st_fail "symlink target: link kept, no sibling written"
      fi

      root="$base/case5b"
      make_root "$root"
      "$CU/ln" -s "$base/does-not-exist" "$root/linux32"
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 2 "$rc" "apply: dangling symlink target refused"
      if [ -L "$root/linux32" ] && [ ! -e "$root/ubuntu12_32" ]; then
        st_pass "dangling symlink: link kept, no sibling written"
      else
        st_fail "dangling symlink: link kept, no sibling written"
      fi

      # 6. Check mode is read-only.
      root="$base/case6"
      make_root "$root"
      before=$(tree_snapshot "$root")
      rc=$(capture do_check "$root" 1)
      expect_rc 1 "$rc" "check: reports recoverable"
      expect_eq "$before" "$(tree_snapshot "$root")" "check: writes nothing"
      if [ -z "$("$FIND" "$root" -maxdepth 1 -name '.steam-repair.*' -print -quit)" ]; then
        st_pass "check: no staging or lock files"
      else
        st_fail "check: no staging or lock files"
      fi

      # 7. The directory-FD lock serializes repair invocations.
      root="$base/case7"
      make_root "$root"
      exec 7<"$root"
      "$FLOCK" -n 7
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 2 "$rc" "apply: concurrent repair refused"
      exec 7<&-
      rc=$(capture do_apply "$root" "$base/good.tar.xz" 1)
      expect_rc 0 "$rc" "apply: succeeds after lock release"

      # 8. A dangling preferred root must not silently select another tree.
      root="$XDG_DATA_HOME/Steam"
      make_root "$root"
      "$CU/mkdir" -p "$HOME/.steam"
      "$CU/ln" -s "$base/absent/parent/Steam" "$HOME/.steam/steam"
      before=$(tree_snapshot "$root")
      rc=$(capture detect_root)
      expect_rc 2 "$rc" "root detection: dangling preferred link refused"
      expect_eq "$before" "$(tree_snapshot "$root")" "root detection: fallback tree unchanged"

      # 9. An early unsafe name must be rejected even beyond a pipe buffer.
      local long_name i
      local -a archive_members=(unsafe-entry)
      printf -v long_name '%0200d' 0
      printf 'fixture\n' > "$base/src/$long_name"
      printf 'unsafe\n' > "$base/src/unsafe-entry"
      for ((i = 0; i < 2048; i++)); do archive_members+=("$long_name"); done
      archive_members+=(ubuntu12_32 linux32)
      "$TAR" --use-compress-program="$XZ" --create --file="$base/large-unsafe.tar.xz" \
        --directory="$base/src" --transform='s|^unsafe-entry$|../unsafe-entry|' \
        "''${archive_members[@]}"
      rc=$(capture validate_archive "$base/large-unsafe.tar.xz")
      expect_rc 2 "$rc" "archive validation: large listing with early unsafe name refused"

      "$CU/rm" -rf -- "$base"
      TEST_BASE=""
      if [ "$ST_FAIL" -eq 0 ]; then
        say "self-test: all checks passed"
        return 0
      fi
      err "self-test: $ST_FAIL check(s) failed"
      return 1
    }

    TEST_BASE=""
    # shellcheck disable=SC2329  # invoked by trap
    cleanup_all() {
      cleanup_stage
      if [ -n "$TEST_BASE" ] && [ -d "$TEST_BASE" ] && [ ! -L "$TEST_BASE" ]; then
        "$CU/rm" -rf -- "$TEST_BASE"
      fi
    }
    trap cleanup_all EXIT

    mode=check
    if [ "$#" -gt 1 ]; then err "too many arguments"; usage >&2; exit 2; fi
    case "''${1:-}" in
      ""|--check) mode=check ;;
      --apply) mode=apply ;;
      --self-test) mode=self-test ;;
      -h|--help) usage; exit 0 ;;
      *) err "unknown argument: $1"; usage >&2; exit 2 ;;
    esac

    if [ "$mode" = self-test ]; then
      self_test
      exit $?
    fi

    if [ -z "''${HOME:-}" ]; then err "HOME is not set"; exit 2; fi
    root=$(detect_root)
    if [ "$mode" = apply ]; then
      do_apply "$root" "$ARCHIVE" 0
      exit $?
    fi
    do_check "$root" 0
    exit $?
  '';
}
