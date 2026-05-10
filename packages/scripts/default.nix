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
}
