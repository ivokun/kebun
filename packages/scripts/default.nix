{pkgs, ...}: {
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.swappy}/bin/swappy -f -
  '';

  screenshot-clipboard = pkgs.writeShellScriptBin "screenshot-clipboard" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy
  '';

  volume-toggle = pkgs.writeShellScriptBin "volume-toggle" ''
    ${pkgs.pulseaudio}/bin/pactl set-default-sink $(${pkgs.pulseaudio}/bin/pactl list short sinks | grep -v "$(${pkgs.pulseaudio}/bin/pactl get-default-sink)" | head -1 | awk '{print $2}')
  '';

  brightness-toggle = pkgs.writeShellScriptBin "brightness-toggle" ''
    if [ "$1" = "up" ]; then
        ${pkgs.brightnessctl}/bin/brightnessctl set 5%+
    elif [ "$1" = "down" ]; then
        ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    fi
  '';

  lock-screen = pkgs.writeShellScriptBin "lock-screen" ''
    loginctl lock-session
  '';

  # Toggle waybar using systemd (UWSM-compatible)
  toggle-waybar = pkgs.writeShellScriptBin "toggle-waybar" ''
    if systemctl --user is-active --quiet waybar; then
      systemctl --user stop waybar
    else
      systemctl --user start waybar
    fi
  '';

  # Toggle nightlight using hyprsunset
  toggle-nightlight = pkgs.writeShellScriptBin "toggle-nightlight" ''
    STATE_FILE="$XDG_RUNTIME_DIR/hyprsunset-active"

    if [ -f "$STATE_FILE" ]; then
      ${pkgs.procps}/bin/pkill hyprsunset
      rm -f "$STATE_FILE"
    else
      ${pkgs.hyprsunset}/bin/hyprsunset -t 4500 &
      touch "$STATE_FILE"
    fi
  '';

  # Restart waybar
  restart-waybar = pkgs.writeShellScriptBin "restart-waybar" ''
    systemctl --user restart waybar
  '';

  # Restart walker
  restart-walker = pkgs.writeShellScriptBin "restart-walker" ''
    ${pkgs.procps}/bin/pkill walker || true
    sleep 0.5
    ${pkgs.walker}/bin/walker &
  '';

  # Color picker
  color-picker = pkgs.writeShellScriptBin "color-picker" ''
    ${pkgs.procps}/bin/pkill hyprpicker || ${pkgs.hyprpicker}/bin/hyprpicker -a
  '';

  # Window pop (float + pin active window)
  window-pop = pkgs.writeShellScriptBin "window-pop" ''
    ${pkgs.hyprland}/bin/hyprctl dispatch togglefloating
    ${pkgs.hyprland}/bin/hyprctl dispatch pin
    ${pkgs.hyprland}/bin/hyprctl dispatch centerwindow
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

  # Waybar module: show icon when flake inputs have updates
  check-waybar-updates = pkgs.writeShellScriptBin "check-waybar-updates" ''
    set -euo pipefail

    FLAKE_DIR="$HOME/Documents/dev/kebun"
    if [ ! -d "$FLAKE_DIR" ]; then
      echo '{"text":"","class":"","alt":""}'
      exit 0
    fi

    cd "$FLAKE_DIR"

    # Check if any input is outdated by comparing locked rev with latest
    # nix flake metadata --json shows locked refs; if they differ from remote, updates exist
    OUTDATED=$(${pkgs.nix}/bin/nix flake metadata --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '
      .locks.nodes.root.inputs[] as $input |
      .locks.nodes[$input] |
      select(.locked) |
      select(.locked.type == "github" or .locked.type == "gitlab" or .locked.type == "sourcehut") |
      .locked.owner + "/" + .locked.repo + ":" + (.locked.rev // "")
    ' | while read -r line; do
      owner_repo="''${line%:*}"
      locked_rev="''${line#*:}"
      [ -z "$locked_rev" ] && continue

      # Fetch latest rev from GitHub API (default branch)
      latest_rev=$(${pkgs.curl}/bin/curl -s "https://api.github.com/repos/$owner_repo/commits/HEAD" | ${pkgs.jq}/bin/jq -r '.sha // empty')
      [ -z "$latest_rev" ] && continue

      if [ "$locked_rev" != "$latest_rev" ]; then
        echo "outdated"
        break
      fi
    done)

    if [ "$OUTDATED" = "outdated" ]; then
      echo '{"text":"󰏗 ","class":"updates","alt":"updates"}'
    else
      echo '{"text":"","class":"","alt":""}'
    fi
  '';

  # Screen recording with wl-screenrec
  screenrecord = pkgs.writeShellScriptBin "screenrecord" ''
    OUTPUT="$HOME/Videos/screenrecord-$(date +%Y%m%d-%H%M%S).mp4"
    mkdir -p "$(dirname "$OUTPUT")"

    if ${pkgs.procps}/bin/pgrep -x wl-screenrec > /dev/null; then
      ${pkgs.procps}/bin/pkill -x wl-screenrec
      ${pkgs.libnotify}/bin/notify-send "Screen recording saved" "$OUTPUT"
    else
      ${pkgs.libnotify}/bin/notify-send "Screen recording started" "Recording to $OUTPUT"
      ${pkgs.wl-screenrec}/bin/wl-screenrec -g "$(${pkgs.slurp}/bin/slurp)" -f "$OUTPUT"
    fi
  '';

  # Audio output switcher
  audio-switch = pkgs.writeShellScriptBin "audio-switch" ''
    DEFAULT_SINK=$(${pkgs.pulseaudio}/bin/pactl get-default-sink)
    SINKS=$(${pkgs.pulseaudio}/bin/pactl list short sinks | ${pkgs.gawk}/bin/awk '{print $2}')

    for sink in $SINKS; do
      if [ "$sink" != "$DEFAULT_SINK" ]; then
        ${pkgs.pulseaudio}/bin/pactl set-default-sink "$sink"
        ${pkgs.libnotify}/bin/notify-send "Audio Output" "Switched to $sink"
        break
      fi
    done
  '';

  # Battery status
  battery-status = pkgs.writeShellScriptBin "battery-status" ''
    set -euo pipefail
    STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    echo "$STATUS"
  '';

  # Battery capacity percentage
  battery-capacity = pkgs.writeShellScriptBin "battery-capacity" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100"
  '';

  # Battery remaining with icon
  battery-remaining = pkgs.writeShellScriptBin "battery-remaining" ''
    set -euo pipefail
    CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
    CAP="''${CAP:-100}"
    STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Charging" ]; then
      ICON="󰂄"
    elif [ "$CAP" -ge 80 ]; then
      ICON="󰁹"
    elif [ "$CAP" -ge 60 ]; then
      ICON="󰂂"
    elif [ "$CAP" -ge 40 ]; then
      ICON="󰂀"
    elif [ "$CAP" -ge 20 ]; then
      ICON="󰁾"
    else
      ICON="󰁺"
    fi
    echo "$ICON $CAP%"
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

  # Background low-battery warning
  battery-monitor = pkgs.writeShellScriptBin "battery-monitor" ''
    set -euo pipefail
    LOCKFILE="$XDG_RUNTIME_DIR/battery-monitor.lock"
    if [ -f "$LOCKFILE" ] && kill -0 "$("${pkgs.coreutils}/bin/cat" "$LOCKFILE")" 2>/dev/null; then
      exit 0
    fi
    echo $$ > "$LOCKFILE"
    trap '"${pkgs.coreutils}/bin/rm" -f "$LOCKFILE"' EXIT
    while true; do
      CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
      STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
      if [ "$STATUS" = "Discharging" ] && [ "$CAP" -le 15 ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Battery Low" "Battery at $CAP% — connect charger!"
      elif [ "$STATUS" = "Discharging" ] && [ "$CAP" -le 25 ]; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Battery" "Battery at $CAP%"
      fi
      ${pkgs.coreutils}/bin/sleep 120
    done
  '';

  # Mic mute toggle with notification
  mic-mute = pkgs.writeShellScriptBin "mic-mute" ''
    set -euo pipefail
    ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle
    MUTE=$(${pkgs.pulseaudio}/bin/pactl get-source-mute @DEFAULT_SOURCE@ | ${pkgs.gnugrep}/bin/grep -oP '(?<=Mute: )\w+')
    if [ "$MUTE" = "yes" ]; then
      ${pkgs.libnotify}/bin/notify-send "Microphone" "Muted" --icon=audio-input-microphone-muted
    else
      ${pkgs.libnotify}/bin/notify-send "Microphone" "Unmuted" --icon=audio-input-microphone
    fi
  '';

  # Toggle window gaps
  toggle-gaps = pkgs.writeShellScriptBin "toggle-gaps" ''
    set -euo pipefail
    STATE_FILE="$XDG_RUNTIME_DIR/hypr-gaps-state"
    if [ -f "$STATE_FILE" ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 5
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 10
      rm -f "$STATE_FILE"
      ${pkgs.libnotify}/bin/notify-send "Gaps" "Normal spacing"
    else
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 0
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 0
      touch "$STATE_FILE"
      ${pkgs.libnotify}/bin/notify-send "Gaps" "No gaps"
    fi
  '';

  # Toggle layout (dwindle/master)
  toggle-layout = pkgs.writeShellScriptBin "toggle-layout" ''
    set -euo pipefail
    CURRENT=$(${pkgs.hyprland}/bin/hyprctl getoption general:layout | ${pkgs.gawk}/bin/awk -F '= ' '{print $2}')
    if [ "$CURRENT" = "dwindle" ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword general:layout master
      ${pkgs.libnotify}/bin/notify-send "Layout" "Master layout"
    else
      ${pkgs.hyprland}/bin/hyprctl keyword general:layout dwindle
      ${pkgs.libnotify}/bin/notify-send "Layout" "Dwindle layout"
    fi
  '';

  # Toggle power profile
  toggle-power-profile = pkgs.writeShellScriptBin "toggle-power-profile" ''
    set -euo pipefail
    if ! CURRENT=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null); then
      ${pkgs.libnotify}/bin/notify-send -u critical "Power Profile" "Failed to read current profile"
      exit 1
    fi
    if [ "$CURRENT" = "power-saver" ]; then
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced
      ${pkgs.libnotify}/bin/notify-send "Power Profile" "Balanced"
    elif [ "$CURRENT" = "balanced" ]; then
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
      ${pkgs.libnotify}/bin/notify-send "Power Profile" "Performance"
    else
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
      ${pkgs.libnotify}/bin/notify-send "Power Profile" "Power Saver"
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
    ${pkgs.libnotify}/bin/notify-send "OCR" "Text copied to clipboard — may persist in clipboard history"
  '';

  # ─── TUI Launch System (inspired by Omarchy) ───
  # Smart focus-or-launch for TUI applications.
  # Prevents duplicate windows: if a window with the given class/title exists,
  # focus it; otherwise launch the command in a new session.
  launch-or-focus = pkgs.writeShellScriptBin "launch-or-focus" ''
    WINDOW_PATTERN="$1"
    LAUNCH_COMMAND="''${2:-uwsm app -- $WINDOW_PATTERN}"

    WINDOW_ADDRESS=$(${pkgs.hyprland}/bin/hyprctl clients -j | \
      ${pkgs.jq}/bin/jq -r --arg p "$WINDOW_PATTERN" '
      .[] | select((.class | test("\\b" + $p + "\\b";"i"))
      or (.title | test("\\b" + $p + "\\b";"i"))) | .address' | \
      ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$WINDOW_ADDRESS" ]; then
      ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow "address:$WINDOW_ADDRESS"
    else
      eval exec setsid $LAUNCH_COMMAND
    fi
  '';

  # Launch a TUI application in a terminal with a unique class.
  # Hyprland matches the class to apply floating/center/size rules.
  launch-tui = pkgs.writeShellScriptBin "launch-tui" ''
    APP_ID="org.kebun.$(${pkgs.coreutils}/bin/basename "$1")"
    exec setsid uwsm app -- ${pkgs.alacritty}/bin/alacritty --class "$APP_ID" -e "$1" "''${@:2}"
  '';

  # Launch or focus wiremix (audio mixer TUI)
  launch-audio = pkgs.writeShellScriptBin "launch-audio" ''
    exec launch-or-focus "org.kebun.wiremix" \
      "${pkgs.alacritty}/bin/alacritty --class org.kebun.wiremix -e wiremix"
  '';

  # Launch or focus impala (Wi-Fi TUI)
  launch-wifi = pkgs.writeShellScriptBin "launch-wifi" ''
    exec launch-or-focus "org.kebun.impala" \
      "${pkgs.alacritty}/bin/alacritty --class org.kebun.impala -e impala"
  '';

  # Launch or focus bluetui (Bluetooth TUI)
  launch-bluetooth = pkgs.writeShellScriptBin "launch-bluetooth" ''
    exec launch-or-focus "org.kebun.bluetui" \
      "${pkgs.alacritty}/bin/alacritty --class org.kebun.bluetui -e bluetui"
  '';

  # Launch or focus btop (system activity TUI)
  launch-activity = pkgs.writeShellScriptBin "launch-activity" ''
    exec launch-or-focus "org.kebun.btop" \
      "${pkgs.alacritty}/bin/alacritty --class org.kebun.btop -e btop"
  '';

  # Launch a one-shot command in a floating terminal
  launch-floating-terminal = pkgs.writeShellScriptBin "launch-floating-terminal" ''
    exec setsid uwsm app -- ${pkgs.alacritty}/bin/alacritty \
      --class org.kebun.terminal -e "$@"
  '';

  # ─── Keybindings Menu ───
  # Parses hyprctl -j binds and shows a searchable menu in Walker
  menu-keybindings = pkgs.writeShellScriptBin "menu-keybindings" ''
    set -euo pipefail

    ${pkgs.hyprland}/bin/hyprctl -j binds | ${pkgs.jq}/bin/jq -r '
      .[] |
      (.modmask | tonumber) as $mod |
      (if $mod == 0 then ""
        elif $mod == 1 then "SHIFT + "
        elif $mod == 4 then "CTRL + "
        elif $mod == 5 then "SHIFT CTRL + "
        elif $mod == 8 then "ALT + "
        elif $mod == 64 then "SUPER + "
        elif $mod == 65 then "SUPER SHIFT + "
        elif $mod == 68 then "SUPER CTRL + "
        elif $mod == 69 then "SUPER SHIFT CTRL + "
        elif $mod == 72 then "SUPER ALT + "
        elif $mod == 73 then "SUPER SHIFT ALT + "
        elif $mod == 76 then "SUPER CTRL ALT + "
        elif $mod == 77 then "SUPER SHIFT CTRL ALT + "
        else "MOD:\($mod) + " end) as $prefix |
      "\($prefix)\(.key | ascii_upcase)  →  \(.description)"
    ' | sort -u | ${pkgs.walker}/bin/walker --dmenu -p "Keybindings"
  '';

  # ─── Capture Menu ───
  menu-capture = pkgs.writeShellScriptBin "menu-capture" ''
    set -euo pipefail

    CHOICE=$(echo -e "Screenshot (edit)\nScreenshot (clipboard)\nScreenshot (OCR)\nColor picker\nScreen recording" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Capture")

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

    CHOICE=$(echo -e "Window transparency\nWindow gaps\nSingle-window square\nNightlight\nIdle locking\nLayout (dwindle/master)\nWaybar" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Toggle")

    case "$CHOICE" in
      "Window transparency")
        ${pkgs.hyprland}/bin/hyprctl dispatch setprop "address:$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.address')" opaque toggle
        ;;
      "Window gaps") toggle-gaps ;;
      "Single-window square") toggle-single-window-square ;;
      "Nightlight") toggle-nightlight ;;
      "Idle locking") ${pkgs.hypridle}/bin/hypridle --toggle ;;
      "Layout (dwindle/master)") toggle-layout ;;
      "Waybar") toggle-waybar ;;
    esac
  '';

  # ─── Hardware Menu ───
  menu-hardware = pkgs.writeShellScriptBin "menu-hardware" ''
    set -euo pipefail

    CHOICE=$(echo -e "Audio controls\nBluetooth controls\nWiFi controls\nBattery status\nPower profile\nBrightness up\nBrightness down\nVolume up\nVolume down" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Hardware")

    case "$CHOICE" in
      "Audio controls") uwsm app -- ${pkgs.pavucontrol}/bin/pavucontrol ;;
      "Bluetooth controls") uwsm app -- ${pkgs.blueman}/bin/blueman-manager ;;
      "WiFi controls") uwsm app -- ${pkgs.networkmanagerapplet}/bin/nm-connection-editor ;;
      "Battery status")
        CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "N/A")
        STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
        ${pkgs.libnotify}/bin/notify-send "Battery" "$CAP% ($STATUS)"
        ;;
      "Power profile") toggle-power-profile ;;
      "Brightness up") swayosd-client --brightness raise ;;
      "Brightness down") swayosd-client --brightness lower ;;
      "Volume up") swayosd-client --output-volume raise ;;
      "Volume down") swayosd-client --output-volume lower ;;
    esac
  '';

  # ─── Kebun Menu ───
  menu-omarchy = pkgs.writeShellScriptBin "menu-omarchy" ''
    set -euo pipefail

    CHOICE=$(echo -e "Terminal\nBrowser\nEditor\nFile manager\nSettings\nLock screen\nActivity monitor\nKeybindings" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Kebun")

    case "$CHOICE" in
      "Terminal") uwsm app -- $TERMINAL ;;
      "Browser") google-chrome ;;
      "Editor") uwsm app -- nvim ;;
      "File manager") uwsm app -- nautilus --new-window ;;
      "Settings") uwsm app -- gnome-control-center ;;
      "Lock screen") ${pkgs.hyprlock}/bin/hyprlock ;;
      "Activity monitor") uwsm app -- ${pkgs.alacritty}/bin/alacritty -e btop ;;
      "Keybindings") menu-keybindings ;;
    esac
  '';

  # ─── Background Menu ───
  menu-background = pkgs.writeShellScriptBin "menu-background" ''
    set -euo pipefail

    CHOICE=$(echo -e "Rose Pine Dawn\nSolid white\nSolid black\nSolid gray" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Background")

    case "$CHOICE" in
      "Rose Pine Dawn") swaybg -c '#faf4ed' -m solid_color ;;
      "Solid white") swaybg -c '#ffffff' -m solid_color ;;
      "Solid black") swaybg -c '#000000' -m solid_color ;;
      "Solid gray") swaybg -c '#808080' -m solid_color ;;
    esac
  '';

  # ─── Theme Menu ───
  menu-theme = pkgs.writeShellScriptBin "menu-theme" ''
    set -euo pipefail

    CHOICE=$(echo -e "Rose Pine Dawn\nRose Pine Moon (dark)" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Theme")

    case "$CHOICE" in
      "Rose Pine Dawn") ${pkgs.libnotify}/bin/notify-send "Theme" "Rose Pine Dawn is active" ;;
      "Rose Pine Moon (dark)") ${pkgs.libnotify}/bin/notify-send "Theme" "Theme switching requires a rebuild" ;;
    esac
  '';

  # ─── Close All Windows ───
  close-all-windows = pkgs.writeShellScriptBin "close-all-windows" ''
    set -euo pipefail
    ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -r '.[].address' | while read -r addr; do
      ${pkgs.hyprland}/bin/hyprctl dispatch closewindow "address:$addr"
    done
  '';

  # ─── Cycle Monitors ───
  cycle-monitors = pkgs.writeShellScriptBin "cycle-monitors" ''
    set -euo pipefail
    CURRENT=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .id')
    TOTAL=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq 'length')
    NEXT=$(( (CURRENT + 1) % TOTAL ))
    ${pkgs.hyprland}/bin/hyprctl dispatch focusmonitor "$NEXT"
  '';

  # ─── Cycle Monitor Scaling ───
  cycle-monitor-scaling = pkgs.writeShellScriptBin "cycle-monitor-scaling" ''
    set -euo pipefail
    MONITOR=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
    CURRENT=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .scale')

    if [ "$CURRENT" = "1.00" ] || [ "$CURRENT" = "1" ]; then
      NEXT="1.25"
    elif [ "$CURRENT" = "1.25" ]; then
      NEXT="1.50"
    elif [ "$CURRENT" = "1.50" ]; then
      NEXT="2.00"
    else
      NEXT="1.00"
    fi

    ${pkgs.hyprland}/bin/hyprctl keyword monitor "$MONITOR,preferred,auto,$NEXT"
    ${pkgs.libnotify}/bin/notify-send "Monitor Scale" "$MONITOR → $NEXT"
  '';

  # ─── Move Waybar Position ───
  move-waybar = pkgs.writeShellScriptBin "move-waybar" ''
    set -euo pipefail
    CONFIG="$HOME/.config/waybar/config"
    [ ! -f "$CONFIG" ] && CONFIG="$HOME/.config/waybar/config.jsonc"

    CURRENT=$(${pkgs.gnugrep}/bin/grep -oP '"position":\s*"\K[^"]+' "$CONFIG" 2>/dev/null || echo "top")

    case "$1" in
      left) NEXT="left" ;;
      right) NEXT="right" ;;
      up) NEXT="top" ;;
      down) NEXT="bottom" ;;
      *)
        case "$CURRENT" in
          top) NEXT="bottom" ;;
          bottom) NEXT="left" ;;
          left) NEXT="right" ;;
          right) NEXT="top" ;;
          *) NEXT="top" ;;
        esac
        ;;
    esac

    ${pkgs.gnused}/bin/sed -i "s/\"position\":\s*\"[^\"]*\"/\"position\": \"$NEXT\"/" "$CONFIG"
    systemctl --user restart waybar
    ${pkgs.libnotify}/bin/notify-send "Waybar" "Position: $NEXT"
  '';

  # ─── File Manager (current directory) ───
  file-manager-cwd = pkgs.writeShellScriptBin "file-manager-cwd" ''
    set -euo pipefail
    CWD=$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workingDirectory // .title // empty')
    [ -z "$CWD" ] && CWD="$HOME"
    [ ! -d "$CWD" ] && CWD="$HOME"
    uwsm app -- nautilus --new-window "$CWD"
  '';

  # ─── Toggle Single-Window Square ───
  toggle-single-window-square = pkgs.writeShellScriptBin "toggle-single-window-square" ''
    set -euo pipefail
    STATE_FILE="$XDG_RUNTIME_DIR/hypr-square-state"
    if [ -f "$STATE_FILE" ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 5
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 10
      ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
      rm -f "$STATE_FILE"
      ${pkgs.libnotify}/bin/notify-send "Layout" "Normal mode"
    else
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 0
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 0
      ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 0
      touch "$STATE_FILE"
      ${pkgs.libnotify}/bin/notify-send "Layout" "Single-window square"
    fi
  '';

  # ─── Toggle Laptop Display ───
  toggle-laptop-display = pkgs.writeShellScriptBin "toggle-laptop-display" ''
    set -euo pipefail
    INTERNAL=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name | test("eDP|LVDS")) | .name' | head -1)
    [ -z "$INTERNAL" ] && INTERNAL="eDP-1"

    DISABLED=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg name "$INTERNAL" '.[] | select(.name == $name) | .disabled' 2>/dev/null || echo "false")

    if [ "$DISABLED" = "true" ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,preferred,auto,1"
      ${pkgs.libnotify}/bin/notify-send "Display" "Internal monitor enabled"
    else
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,disable"
      ${pkgs.libnotify}/bin/notify-send "Display" "Internal monitor disabled"
    fi
  '';

  # ─── Toggle Mirror Display ───
  toggle-mirror-display = pkgs.writeShellScriptBin "toggle-mirror-display" ''
    set -euo pipefail
    MONITORS=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[].name')
    COUNT=$(echo "$MONITORS" | ${pkgs.coreutils}/bin/wc -l)

    if [ "$COUNT" -lt 2 ]; then
      ${pkgs.libnotify}/bin/notify-send "Display" "Only one monitor connected"
      exit 0
    fi

    PRIMARY=$(echo "$MONITORS" | ${pkgs.coreutils}/bin/head -1)
    SECONDARY=$(echo "$MONITORS" | ${pkgs.coreutils}/bin/tail -1)

    ${pkgs.hyprland}/bin/hyprctl keyword monitor "$SECONDARY,preferred,auto,1,mirror,$PRIMARY"
    ${pkgs.libnotify}/bin/notify-send "Display" "Mirroring $PRIMARY to $SECONDARY"
  '';

  # ─── Screen Recording Menu ───
  screenrecord-menu = pkgs.writeShellScriptBin "screenrecord-menu" ''
    set -euo pipefail

    CHOICE=$(echo -e "Record region\nRecord screen\nStop recording" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Screen Record")

    case "$CHOICE" in
      "Record region") screenrecord ;;
      "Record screen")
        OUTPUT="$HOME/Videos/screenrecord-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).mp4"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$OUTPUT")"
        ${pkgs.libnotify}/bin/notify-send "Screen recording started" "Recording to $OUTPUT"
        ${pkgs.wl-screenrec}/bin/wl-screenrec -f "$OUTPUT"
        ;;
      "Stop recording")
        if ${pkgs.procps}/bin/pgrep -x wl-screenrec > /dev/null; then
          ${pkgs.procps}/bin/pkill -x wl-screenrec
          ${pkgs.libnotify}/bin/notify-send "Screen recording stopped"
        fi
        ;;
    esac
  '';

  # ─── LocalSend Share ───
  localsend-share = pkgs.writeShellScriptBin "localsend-share" ''
    set -euo pipefail
    uwsm app -- localsend
  '';

  # ─── Show Battery ───
  show-battery = pkgs.writeShellScriptBin "show-battery" ''
    set -euo pipefail
    CAP=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "N/A")
    STATUS=$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    TIME=$(battery-remaining-time 2>/dev/null || echo "N/A")
    ${pkgs.libnotify}/bin/notify-send "Battery" "$CAP% ($STATUS)\nRemaining: $TIME"
  '';

  # ─── Show Time ───
  show-time = pkgs.writeShellScriptBin "show-time" ''
    set -euo pipefail
    TIME=$(${pkgs.coreutils}/bin/date "+%I:%M %p")
    DATE=$(${pkgs.coreutils}/bin/date "+%A, %B %d, %Y")
    ${pkgs.libnotify}/bin/notify-send "Time" "$TIME\n$DATE"
  '';

  # ─── Show Weather ───
  show-weather = pkgs.writeShellScriptBin "show-weather" ''
    set -euo pipefail
    LOCATION=$(${pkgs.curl}/bin/curl -s "https://ipapi.co/json/" | ${pkgs.jq}/bin/jq -r '.city // "Tokyo"')
    WEATHER=$(${pkgs.curl}/bin/curl -s "https://wttr.in/$LOCATION?format=%C+%t+%w" 2>/dev/null || echo "Unable to fetch weather")
    ${pkgs.libnotify}/bin/notify-send "Weather in $LOCATION" "$WEATHER"
  '';

  # ─── Reminders ───
  reminder-set = pkgs.writeShellScriptBin "reminder-set" ''
    set -euo pipefail
    REMINDER_FILE="$XDG_DATA_HOME/kebun-reminders.txt"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$REMINDER_FILE")"

    INPUT=$(${pkgs.coreutils}/bin/echo "" | ${pkgs.walker}/bin/walker --dmenu -p "Reminder" 2>/dev/null || true)
    [ -z "$INPUT" ] && exit 0

    echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M')] $INPUT" >> "$REMINDER_FILE"
    ${pkgs.libnotify}/bin/notify-send "Reminder Set" "$INPUT"
  '';

  reminder-show = pkgs.writeShellScriptBin "reminder-show" ''
    set -euo pipefail
    REMINDER_FILE="$XDG_DATA_HOME/kebun-reminders.txt"
    if [ ! -f "$REMINDER_FILE" ] || [ ! -s "$REMINDER_FILE" ]; then
      ${pkgs.libnotify}/bin/notify-send "Reminders" "No reminders set"
      exit 0
    fi

    CONTENT=$(${pkgs.coreutils}/bin/tail -20 "$REMINDER_FILE")
    ${pkgs.libnotify}/bin/notify-send "Reminders" "$CONTENT"
  '';

  reminder-clear = pkgs.writeShellScriptBin "reminder-clear" ''
    set -euo pipefail
    REMINDER_FILE="$XDG_DATA_HOME/kebun-reminders.txt"
    [ -f "$REMINDER_FILE" ] && ${pkgs.coreutils}/bin/rm -f "$REMINDER_FILE"
    ${pkgs.libnotify}/bin/notify-send "Reminders" "All reminders cleared"
  '';

  # ─── Dictation ───
  dictation-toggle = pkgs.writeShellScriptBin "dictation-toggle" ''
    set -euo pipefail
    if command -v hyprwhspr-rs >/dev/null 2>&1; then
      hyprwhspr-rs record toggle
      ${pkgs.libnotify}/bin/notify-send "Dictation" "Toggled recording"
    else
      ${pkgs.libnotify}/bin/notify-send "Dictation" "hyprwhspr-rs not installed"
    fi
  '';

  dictation-ptt = pkgs.writeShellScriptBin "dictation-ptt" ''
    set -euo pipefail
    if command -v hyprwhspr-rs >/dev/null 2>&1; then
      hyprwhspr-rs record start
    else
      ${pkgs.libnotify}/bin/notify-send "Dictation" "hyprwhspr-rs not installed"
    fi
  '';

  dictation-ptt-release = pkgs.writeShellScriptBin "dictation-ptt-release" ''
    set -euo pipefail
    if command -v hyprwhspr-rs >/dev/null 2>&1; then
      hyprwhspr-rs record stop
    fi
  '';

  # ─── Transcode ───
  transcode = pkgs.writeShellScriptBin "transcode" ''
    set -euo pipefail

    CHOICE=$(${pkgs.coreutils}/bin/echo -e "Compress video\nExtract audio\nConvert to MP4\nConvert to WebM" | \
      ${pkgs.walker}/bin/walker --dmenu -p "Transcode")

    # Use active window's working directory or home
    CWD=$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')
    [ -z "$CWD" ] \&\& CWD="$HOME"
    cd "$CWD"

    case "$CHOICE" in
      "Compress video")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f -printf '%P\n' | ${pkgs.walker}/bin/walker --dmenu -p "Select video" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}-compressed.mp4"
        ${pkgs.ffmpeg}/bin/ffmpeg -y -i "$FILE" -vcodec libx264 -crf 23 -preset fast "$OUTPUT"
        ${pkgs.libnotify}/bin/notify-send "Transcode" "Compressed: $OUTPUT"
        ;;
      "Extract audio")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f -printf '%P\n' | ${pkgs.walker}/bin/walker --dmenu -p "Select video" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}.mp3"
        ${pkgs.ffmpeg}/bin/ffmpeg -y -i "$FILE" -vn -acodec libmp3lame -q:a 2 "$OUTPUT"
        ${pkgs.libnotify}/bin/notify-send "Transcode" "Audio extracted: $OUTPUT"
        ;;
      "Convert to MP4")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f -printf '%P\n' | ${pkgs.walker}/bin/walker --dmenu -p "Select file" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}.mp4"
        ${pkgs.ffmpeg}/bin/ffmpeg -y -i "$FILE" -c:v libx264 -c:a aac "$OUTPUT"
        ${pkgs.libnotify}/bin/notify-send "Transcode" "Converted: $OUTPUT"
        ;;
      "Convert to WebM")
        FILE=$(${pkgs.findutils}/bin/find . -maxdepth 1 -type f -printf '%P\n' | ${pkgs.walker}/bin/walker --dmenu -p "Select file" || true)
        [ -z "$FILE" ] \&\& exit 0
        OUTPUT="''${FILE%.*}.webm"
        ${pkgs.ffmpeg}/bin/ffmpeg -y -i "$FILE" -c:v libvpx-vp9 -c:a libopus "$OUTPUT"
        ${pkgs.libnotify}/bin/notify-send "Transcode" "Converted: $OUTPUT"
        ;;
    esac
  '';

  # ─── Cursor Zoom ───
  cursor-zoom = pkgs.writeShellScriptBin "cursor-zoom" ''
    set -euo pipefail
    if ! ${pkgs.procps}/bin/pgrep -x hyprmagnifier > /dev/null; then
      uwsm app -- hyprmagnifier &
      ${pkgs.libnotify}/bin/notify-send "Cursor Zoom" "Magnifier enabled"
    else
      ${pkgs.libnotify}/bin/notify-send "Cursor Zoom" "Magnifier already running"
    fi
  '';

  cursor-zoom-reset = pkgs.writeShellScriptBin "cursor-zoom-reset" ''
    set -euo pipefail
    if ${pkgs.procps}/bin/pgrep -x hyprmagnifier > /dev/null; then
      ${pkgs.procps}/bin/pkill -x hyprmagnifier
      ${pkgs.libnotify}/bin/notify-send "Cursor Zoom" "Magnifier disabled"
    fi
  '';
}
