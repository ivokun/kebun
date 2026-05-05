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
}
