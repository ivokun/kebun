{pkgs, ...}: {
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.swappy}/bin/swappy -f -
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
}
