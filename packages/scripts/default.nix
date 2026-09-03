{
  pkgs,
  # The compositor's own hyprctl (the flake input), not nixpkgs' pkgs.hyprland —
  # the two versions drift and a mismatched client misleads hyprctl-driven scripts.
  # Callers pass inputs.hyprland.packages.${system}.hyprland.
  hyprland ? pkgs.hyprland,
  ...
}: let
  palette = import ../../lib/palette.nix;
in {
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.swappy}/bin/swappy -f -
  '';

  screenshot-clipboard = pkgs.writeShellScriptBin "screenshot-clipboard" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy
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

  # Screen recording with wl-screenrec
  screenrecord = pkgs.writeShellScriptBin "screenrecord" ''
    OUTPUT="$HOME/Videos/screenrecord-$(date +%Y%m%d-%H%M%S).mp4"
    mkdir -p "$(dirname "$OUTPUT")"

    if ${pkgs.procps}/bin/pgrep -x wl-screenrec > /dev/null; then
      ${pkgs.procps}/bin/pkill -x wl-screenrec
      omarchy-notification-send "Screen recording saved" "$OUTPUT"
    else
      omarchy-notification-send "Screen recording started" "Recording to $OUTPUT"
      ${pkgs.wl-screenrec}/bin/wl-screenrec -g "$(${pkgs.slurp}/bin/slurp)" -f "$OUTPUT"
    fi
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

  # Screenshot OCR
  screenshot-ocr = pkgs.writeShellScriptBin "screenshot-ocr" ''
    set -euo pipefail
    TMPDIR="''${XDG_RUNTIME_DIR:-/tmp}"
    TMPFILE=$(${pkgs.coreutils}/bin/mktemp -p "$TMPDIR" ocr-XXXXXX.png)
    trap '${pkgs.coreutils}/bin/rm -f "$TMPFILE"' EXIT
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$TMPFILE"
    ${pkgs.tesseract}/bin/tesseract "$TMPFILE" stdout | ${pkgs.wl-clipboard}/bin/wl-copy
    omarchy-notification-send "OCR" "Text copied to clipboard — may persist in clipboard history"
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

  # ─── Capture Menu ───
  menu-capture = pkgs.writeShellScriptBin "menu-capture" ''
    set -euo pipefail

    CHOICE=$(echo -e "Screenshot (edit)\nScreenshot (clipboard)\nScreenshot (OCR)\nColor picker\nScreen recording" | \
      omarchy-menu-select "Capture")

    case "$CHOICE" in
      "Screenshot (edit)") screenshot ;;
      "Screenshot (clipboard)") screenshot-clipboard ;;
      "Screenshot (OCR)") screenshot-ocr ;;
      "Color picker") color-picker ;;
      "Screen recording") screenrecord ;;
    esac
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

    CHOICE=$(echo -e "Audio controls\nBluetooth controls\nWiFi controls\nBattery status\nPower profile\nBrightness up\nBrightness down\nVolume up\nVolume down" | \
      omarchy-menu-select "Hardware")

    case "$CHOICE" in
      "Audio controls") uwsm app -- ${pkgs.pavucontrol}/bin/pavucontrol ;;
      "Bluetooth controls") uwsm app -- ${pkgs.blueman}/bin/blueman-manager ;;
      "WiFi controls") launch-wifi ;;
      "Battery status") omarchy-notification-battery ;;
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
      "Browser") ${pkgs.google-chrome}/bin/google-chrome ;;
      "Editor") uwsm app -- ${pkgs.neovim}/bin/nvim ;;
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
      "Rose Pine Dawn") ${pkgs.swaybg}/bin/swaybg -c '${palette.background}' -m solid_color ;;
      "Solid white") ${pkgs.swaybg}/bin/swaybg -c '#ffffff' -m solid_color ;;
      "Solid black") ${pkgs.swaybg}/bin/swaybg -c '#000000' -m solid_color ;;
      "Solid gray") ${pkgs.swaybg}/bin/swaybg -c '#808080' -m solid_color ;;
    esac
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
    CWD=$(${hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')
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

  # ─── Screen Recording Menu ───
  screenrecord-menu = pkgs.writeShellScriptBin "screenrecord-menu" ''
    set -euo pipefail

    CHOICE=$(echo -e "Record region\nRecord screen\nStop recording" | \
      omarchy-menu-select "Screen Record")

    case "$CHOICE" in
      "Record region") screenrecord ;;
      "Record screen")
        OUTPUT="$HOME/Videos/screenrecord-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).mp4"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$OUTPUT")"
        OUTPUT_GEOM=$(${hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | "\(.width)x\(.height)+\(.x),\(.y)"')
        omarchy-notification-send "Screen recording started" "Recording to $OUTPUT"
        ${pkgs.wl-screenrec}/bin/wl-screenrec -g "$OUTPUT_GEOM" -f "$OUTPUT"
        ;;
      "Stop recording")
        if ${pkgs.procps}/bin/pgrep -x wl-screenrec > /dev/null; then
          ${pkgs.procps}/bin/pkill -x wl-screenrec
          omarchy-notification-send "Screen recording stopped"
        fi
        ;;
    esac
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
    CWD=$(${hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')
    [ -z "$CWD" ] \&\& CWD="$HOME"
    cd "$CWD"

    case "$CHOICE" in
      "Compress video")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select video" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}-compressed.mp4"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -vcodec libx264 -crf 23 -preset fast "$OUTPUT"
        omarchy-notification-send "Transcode" "Compressed: $OUTPUT"
        ;;
      "Extract audio")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select video" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}.mp3"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -vn -acodec libmp3lame -q:a 2 "$OUTPUT"
        omarchy-notification-send "Transcode" "Audio extracted: $OUTPUT"
        ;;
      "Convert to MP4")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select file" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}.mp4"
        ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$FILE" -c:v libx264 -c:a aac "$OUTPUT"
        omarchy-notification-send "Transcode" "Converted: $OUTPUT"
        ;;
      "Convert to WebM")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) -printf '%P\n' | omarchy-menu-select "Select file" || true)
        [ -z "$FILE" ] \&\& exit 0
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
}
