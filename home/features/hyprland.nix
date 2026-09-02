{
  config,
  lib,
  pkgs,
  inputs,
  username,
  system,
  ...
}: {
  # ─── Hyprland — Lua layer (ADR-0007 Stage 3) ───
  #
  # The compositor config ships as the Lua files emitted below
  # (~/.config/hypr/*.lua). Hyprland ≥0.53 auto-prefers hyprland.lua over
  # hyprland.conf when both exist, so the HM-generated hyprland.conf (built
  # from the minimal module options kept here) is inert. The entry file
  # ~/.config/hypr/hyprland.lua loads the vendored upstream defaults from
  # $OMARCHY_PATH and then kebun's overrides.
  #
  # ADR-0007 Stage 4 retired the v3 shell stack (waybar, walker, mako, swayosd,
  # hypridle, hyprlock, hyprsunset, polkit-gnome): the vendored Omarchy v4
  # QuickShell — omarchy-shell plus the omarchy-* session verbs — now provides
  # the bar, menus, OSD, notifications, lock and idle handling. The theme
  # engine swap is Stage 5.
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    systemd = {
      enable = true;
      variables = ["--all"];
    };

    # `settings` is deliberately gone: every monitor/env/input/decoration/
    # windowrule/bind/exec-once value moved to the Lua files below.
  };

  # Bare commands the Lua layer needs that nothing else put on PATH:
  # - hyprctl must be the compositor's own build (flake input), not nixpkgs';
  #   the shell's verbs and kebun's scripts read it
  # - pavucontrol is the audio panel (SUPER+CTRL+A)
  # - hyprsunset is the nightlight binary — the shell's
  #   omarchy-toggle-nightlight verb drives it via `hyprctl hyprsunset temperature`
  home.packages = [
    inputs.hyprland.packages.${pkgs.system}.hyprland
    pkgs.pavucontrol
    pkgs.hyprsunset
  ];

  # ─── Lua layer entry ───
  xdg.configFile."hypr/hyprland.lua".text = ''
    -- Kebun Hyprland entry — Omarchy v4 Lua layer (ADR-0007 Stage 3).
    dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

    -- Kebun keeps its own keymap; upstream default bindings stay off.
    omarchy_default_bindings = false
    omarchy_preinstalled_bindings = false

    -- Upstream defaults, minus default.hypr.autostart (kebun launches the shell
    -- itself — under uwsm, see hypr/autostart.lua — and skips upstream's
    -- provisioning hooks) and minus the gated bindings/* (see kill-switches above).
    require("default.hypr.helpers")
    require("default.hypr.envs")
    require("default.hypr.looknfeel")
    require("default.hypr.input")
    require("default.hypr.windows")
    require("default.hypr.require_optional").module("omarchy.current.theme.hyprland")

    -- Kebun overrides, loaded after the defaults so they win.
    require("hypr.envs")
    require("hypr.monitors")
    require("hypr.input")
    require("hypr.bindings")
    require("hypr.windows")
    require("hypr.looknfeel")
    require("hypr.autostart")

    -- Deliberately absent vs the reference entry: default.hypr.toggles (kebun has
    -- its own toggle scripts, no ~/.local/state/omarchy/toggles tree) and hyprmon
    -- (no HyprMon; a plain require would error without the file).
  '';

  # Kebun env deltas over upstream default/hypr/envs.lua. Upstream already sets
  # XCURSOR_SIZE/HYPRCURSOR_SIZE 24, GDK_BACKEND wayland,x11,*, QT_QPA_PLATFORM
  # wayland;xcb, MOZ_ENABLE_WAYLAND, ELECTRON_OZONE_PLATFORM_HINT, OZONE_PLATFORM,
  # XDG_SESSION_TYPE/DESKTOP/CURRENT_DESKTOP, xwayland.force_zero_scaling and
  # ecosystem.no_update_news — identical to kebun's old env list, so they are not
  # re-set here (last-writer-wins would make a re-set pointless anyway).
  xdg.configFile."hypr/envs.lua".text = ''
    -- Kebun environment deltas over default/hypr/envs.lua (ADR-0007 Stage 3).

    -- Kvantum styling for Qt apps.
    hl.env("QT_STYLE_OVERRIDE", "kvantum")

    -- Carried over from the old env block.
    hl.env("SDL_VIDEODRIVER", "wayland")
    hl.env("GDK_SCALE", "1")
    hl.env("TERMINAL", "alacritty")

    -- Japanese input method (fcitx5-mozc).
    hl.env("GTK_IM_MODULE", "fcitx")
    hl.env("QT_IM_MODULE", "fcitx")
    hl.env("XMODIFIERS", "@im=fcitx")
  '';

  xdg.configFile."hypr/monitors.lua".text = ''
    -- Kebun monitor layout — moved verbatim from home/sakura.nix (ADR-0007
    -- Stage 3). sakura-specific values (X13 built-in panel + HDMI + 4K DP);
    -- verify against the machine on next deploy — backlog §3.1.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
    hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.00", position = "2272x1440", scale = 1.00 })
    hl.monitor({ output = "DP-2", mode = "3840x2160@60.00", position = "1920x0", scale = 1.5 })
  '';

  xdg.configFile."hypr/input.lua".text = ''
    -- Kebun input overrides — ported from the old hyprland.conf input block
    -- (ADR-0007 Stage 3). Loads after default/hypr/input.lua, so these win:
    -- repeat_delay 600 (upstream 250) and kb_options compose:caps (upstream
    -- adds shift:both_capslock_cancel). Upstream's clickfinger_behavior and
    -- the misc DPMS keys are accepted as-is. Hyprland 0.56 Lua uses snake_case
    -- keys — the old conf's hyphenated tap-to-click is corrected to
    -- tap_to_click here.
    hl.config({
      input = {
        kb_layout = "us",
        kb_options = "compose:caps",
        follow_mouse = 1,
        sensitivity = 0,
        repeat_rate = 40,
        repeat_delay = 600,
        numlock_by_default = true,

        touchpad = {
          natural_scroll = true,
          scroll_factor = 0.4,
          disable_while_typing = true,
          tap_to_click = true,
          drag_lock = false,
          middle_button_emulation = true,
        },
      },
    })
  '';

  xdg.configFile."hypr/bindings.lua".text = ''
    -- Kebun keybindings — ported from the old hyprland.conf bindd list
    -- (ADR-0007 Stage 3); Stage 4 re-pointed the launcher/menu, OSD,
    -- notification, lock and idle binds at the Omarchy v4 shell verbs, with
    -- kebun's own scripts kept. Descriptions are load-bearing:
    -- omarchy-menu-keybindings reads `hyprctl binds`, which exposes them, so
    -- keep every call on one line. Binds with a nil description are invisible
    -- to the menu, matching the old plain bind/bindr/bindl/bindm entries.
    --
    -- Flag notes:
    -- - Media and brightness keys adopt upstream's flags: { locked = true,
    --   repeating = true } for the hold-to-repeat raise/lower pairs, plain
    --   { locked = true } for mute/play/pause/next/prev/micmute.
    -- - The lid-switch binds need { locked = true } so they fire while locked.
    -- - String dispatchers are exec'd directly (no uwsm wrapping); GUI
    --   launches keep kebun's `uwsm app --` prefix in the command itself.

    -- SUPER+C/V/X use the same down/up split as upstream's clipboard binds:
    -- Hyprland's send_shortcut sometimes leaves synthetic key state
    -- stuck/repeating when sent as one chord from inside a held modifier.
    -- https://github.com/hyprwm/Hyprland/discussions/14099
    local function send_shortcut_once(mods, key)
      return function()
        hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

        hl.timer(function()
          hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
        end, { timeout = 50, type = "oneshot" })
      end
    end

    -- ─── Application Launchers ───
    o.bind("SUPER + RETURN", "Terminal", "uwsm app -- alacritty --working-directory=\"$(pwd)\"")
    o.bind("SUPER + SHIFT + F", "File manager", "uwsm app -- nautilus --new-window")
    o.bind("SUPER + B", "Browser", "google-chrome")
    o.bind("SUPER + SHIFT + B", "Browser (private)", "google-chrome --private")
    o.bind("SUPER + N", "Editor", "uwsm app -- nvim")
    o.bind("SUPER + D", "Docker", "uwsm app -- alacritty -e lazydocker")
    o.bind("SUPER + O", "Obsidian", "uwsm app -- obsidian -disable-gpu --enable-wayland-ime")
    o.bind("SUPER + SHIFT + O", "Pop window", "window-pop")

    -- ─── Menus ───
    o.bind("SUPER + SPACE", "Launch apps", "omarchy-menu toggle apps")
    o.bind("SUPER + CTRL + E", "Emoji picker", "omarchy-shell shell toggle omarchy.emojis")
    -- SUPER CTRL SPACE belongs to the Background menu further down.
    o.bind("SUPER + ESCAPE", "System menu", "omarchy-menu toggle system")
    o.bind("XF86PowerOff", "Power menu", "omarchy-menu toggle system", { locked = true })
    o.bind("SUPER + K", "Show keybindings", "omarchy-menu-keybindings")
    o.bind("SUPER + A", "Web apps", "menu-webapp")

    -- ─── Window Management ───
    o.bind("SUPER + W", "Close window", hl.dsp.window.close())
    o.bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
    o.bind("SUPER + P", "Pseudo window", hl.dsp.window.pseudo())
    o.bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
    o.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
    o.bind("SUPER + CTRL + F", "Tiled full screen", "hyprctl dispatch fullscreenstate 0 2")
    o.bind("SUPER + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
    o.bind("SUPER + L", "Toggle workspace layout", "hyprctl dispatch layoutmsg orientationnext")

    -- ─── Focus Movement ───
    o.bind("SUPER + LEFT", "Move window focus left", hl.dsp.focus({ direction = "l" }))
    o.bind("SUPER + RIGHT", "Move window focus right", hl.dsp.focus({ direction = "r" }))
    o.bind("SUPER + UP", "Move window focus up", hl.dsp.focus({ direction = "u" }))
    o.bind("SUPER + DOWN", "Move window focus down", hl.dsp.focus({ direction = "d" }))

    -- ─── Workspace Switching ───
    o.bind("SUPER + code:10", "Switch to workspace 1", hl.dsp.focus({ workspace = "1" }))
    o.bind("SUPER + code:11", "Switch to workspace 2", hl.dsp.focus({ workspace = "2" }))
    o.bind("SUPER + code:12", "Switch to workspace 3", hl.dsp.focus({ workspace = "3" }))
    o.bind("SUPER + code:13", "Switch to workspace 4", hl.dsp.focus({ workspace = "4" }))
    o.bind("SUPER + code:14", "Switch to workspace 5", hl.dsp.focus({ workspace = "5" }))
    o.bind("SUPER + code:15", "Switch to workspace 6", hl.dsp.focus({ workspace = "6" }))
    o.bind("SUPER + code:16", "Switch to workspace 7", hl.dsp.focus({ workspace = "7" }))
    o.bind("SUPER + code:17", "Switch to workspace 8", hl.dsp.focus({ workspace = "8" }))
    o.bind("SUPER + code:18", "Switch to workspace 9", hl.dsp.focus({ workspace = "9" }))
    o.bind("SUPER + code:19", "Switch to workspace 10", hl.dsp.focus({ workspace = "10" }))

    -- ─── Move Window to Workspace ───
    o.bind("SUPER + SHIFT + code:10", "Move window to workspace 1", hl.dsp.window.move({ workspace = "1" }))
    o.bind("SUPER + SHIFT + code:11", "Move window to workspace 2", hl.dsp.window.move({ workspace = "2" }))
    o.bind("SUPER + SHIFT + code:12", "Move window to workspace 3", hl.dsp.window.move({ workspace = "3" }))
    o.bind("SUPER + SHIFT + code:13", "Move window to workspace 4", hl.dsp.window.move({ workspace = "4" }))
    o.bind("SUPER + SHIFT + code:14", "Move window to workspace 5", hl.dsp.window.move({ workspace = "5" }))
    o.bind("SUPER + SHIFT + code:15", "Move window to workspace 6", hl.dsp.window.move({ workspace = "6" }))
    o.bind("SUPER + SHIFT + code:16", "Move window to workspace 7", hl.dsp.window.move({ workspace = "7" }))
    o.bind("SUPER + SHIFT + code:17", "Move window to workspace 8", hl.dsp.window.move({ workspace = "8" }))
    o.bind("SUPER + SHIFT + code:18", "Move window to workspace 9", hl.dsp.window.move({ workspace = "9" }))
    o.bind("SUPER + SHIFT + code:19", "Move window to workspace 10", hl.dsp.window.move({ workspace = "10" }))

    -- ─── Move Window Silently ───
    o.bind("SUPER + SHIFT + ALT + code:10", "Move window silently to workspace 1", hl.dsp.window.move({ workspace = "1", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:11", "Move window silently to workspace 2", hl.dsp.window.move({ workspace = "2", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:12", "Move window silently to workspace 3", hl.dsp.window.move({ workspace = "3", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:13", "Move window silently to workspace 4", hl.dsp.window.move({ workspace = "4", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:14", "Move window silently to workspace 5", hl.dsp.window.move({ workspace = "5", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:15", "Move window silently to workspace 6", hl.dsp.window.move({ workspace = "6", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:16", "Move window silently to workspace 7", hl.dsp.window.move({ workspace = "7", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:17", "Move window silently to workspace 8", hl.dsp.window.move({ workspace = "8", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:18", "Move window silently to workspace 9", hl.dsp.window.move({ workspace = "9", follow = false }))
    o.bind("SUPER + SHIFT + ALT + code:19", "Move window silently to workspace 10", hl.dsp.window.move({ workspace = "10", follow = false }))

    -- ─── Scratchpad ───
    o.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
    o.bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

    -- ─── Workspace Cycling ───
    o.bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
    o.bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
    o.bind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))

    -- ─── Move Workspace to Monitor ───
    o.bind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
    o.bind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
    o.bind("SUPER + SHIFT + ALT + UP", "Move workspace to up monitor", hl.dsp.workspace.move({ monitor = "u" }))
    o.bind("SUPER + SHIFT + ALT + DOWN", "Move workspace to down monitor", hl.dsp.workspace.move({ monitor = "d" }))

    -- ─── Swap Windows ───
    o.bind("SUPER + SHIFT + LEFT", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
    o.bind("SUPER + SHIFT + RIGHT", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
    o.bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
    o.bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

    -- ─── Cycle Windows ───
    o.bind("ALT + TAB", "Cycle to next window", hl.dsp.window.cycle_next())
    o.bind("ALT + SHIFT + TAB", "Cycle to prev window", hl.dsp.window.cycle_next({ next = false }))

    -- ─── Resize ───
    o.bind("SUPER + code:20", "Shrink window width", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
    o.bind("SUPER + code:21", "Expand window width", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
    o.bind("SUPER + SHIFT + code:20", "Shrink window height", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
    o.bind("SUPER + SHIFT + code:21", "Expand window height", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
    o.bind("SUPER + ALT + code:20", "Shrink window width (fine)", hl.dsp.window.resize({ x = -25, y = 0, relative = true }))
    o.bind("SUPER + ALT + code:21", "Expand window width (fine)", hl.dsp.window.resize({ x = 25, y = 0, relative = true }))
    o.bind("SUPER + ALT + SHIFT + code:20", "Shrink window height (fine)", hl.dsp.window.resize({ x = 0, y = -25, relative = true }))
    o.bind("SUPER + ALT + SHIFT + code:21", "Expand window height (fine)", hl.dsp.window.resize({ x = 0, y = 25, relative = true }))
    o.bind("SUPER + CTRL + code:20", "Shrink window width (coarse)", hl.dsp.window.resize({ x = -300, y = 0, relative = true }))
    o.bind("SUPER + CTRL + code:21", "Expand window width (coarse)", hl.dsp.window.resize({ x = 300, y = 0, relative = true }))
    o.bind("SUPER + CTRL + SHIFT + code:20", "Shrink window height (coarse)", hl.dsp.window.resize({ x = 0, y = -300, relative = true }))
    o.bind("SUPER + CTRL + SHIFT + code:21", "Expand window height (coarse)", hl.dsp.window.resize({ x = 0, y = 300, relative = true }))

    -- ─── Groups ───
    o.bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
    o.bind("SUPER + ALT + G", "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))
    o.bind("SUPER + ALT + LEFT", "Move window to group on left", hl.dsp.window.move({ into_group = "l" }))
    o.bind("SUPER + ALT + RIGHT", "Move window to group on right", hl.dsp.window.move({ into_group = "r" }))
    o.bind("SUPER + ALT + UP", "Move window to group on top", hl.dsp.window.move({ into_group = "u" }))
    o.bind("SUPER + ALT + DOWN", "Move window to group on bottom", hl.dsp.window.move({ into_group = "d" }))
    o.bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
    o.bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())
    o.bind("SUPER + CTRL + LEFT", "Move grouped window focus left", hl.dsp.group.prev())
    o.bind("SUPER + CTRL + RIGHT", "Move grouped window focus right", hl.dsp.group.next())

    -- ─── Clipboard ───
    o.bind("SUPER + CTRL + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")

    -- ─── Mouse Bindings (wheel) ───
    o.bind("SUPER + mouse_down", "Scroll workspace forward", hl.dsp.focus({ workspace = "e+1" }))
    o.bind("SUPER + mouse_up", "Scroll workspace backward", hl.dsp.focus({ workspace = "e-1" }))

    -- ─── Media Keys ───
    o.bind("XF86AudioRaiseVolume", "Volume up", "omarchy-audio-output-volume raise", { locked = true, repeating = true })
    o.bind("XF86AudioLowerVolume", "Volume down", "omarchy-audio-output-volume lower", { locked = true, repeating = true })
    o.bind("XF86AudioMute", "Mute", "omarchy-audio-output-volume mute-toggle", { locked = true })
    o.bind("XF86AudioMicMute", "Mute microphone", "omarchy-audio-input-mute", { locked = true })
    o.bind("XF86MonBrightnessUp", "Brightness up", "omarchy-brightness-display +5%", { locked = true, repeating = true })
    o.bind("XF86MonBrightnessDown", "Brightness down", "omarchy-brightness-display 5%-", { locked = true, repeating = true })

    -- ─── Precise Media Adjustments ───
    o.bind("ALT + XF86AudioRaiseVolume", "Volume up precise", "omarchy-audio-output-volume +1", { locked = true, repeating = true })
    o.bind("ALT + XF86AudioLowerVolume", "Volume down precise", "omarchy-audio-output-volume -1", { locked = true, repeating = true })
    o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", "omarchy-brightness-display +1%", { locked = true, repeating = true })
    o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", "omarchy-brightness-display 1%-", { locked = true, repeating = true })

    -- ─── Media Playback ───
    o.bind("XF86AudioNext", "Next track", "playerctl next", { locked = true })
    o.bind("XF86AudioPause", "Pause", "playerctl play-pause", { locked = true })
    o.bind("XF86AudioPlay", "Play", "playerctl play-pause", { locked = true })
    o.bind("XF86AudioPrev", "Previous track", "playerctl previous", { locked = true })

    -- ─── Audio Output Switch ───
    o.bind("SUPER + XF86AudioMute", "Switch audio output", "omarchy-audio-output-switch", { locked = true })

    -- ─── Music Player ───
    o.bind("SUPER + SHIFT + ALT + M", "Launch cliamp", "uwsm app -- alacritty -e cliamp")

    -- ─── Aesthetics ───
    o.bind("SUPER + SHIFT + SPACE", "Toggle top bar", "omarchy-toggle-bar")
    o.bind("SUPER + BACKSPACE", "Toggle window transparency", "hyprctl dispatch setprop \"address:$(hyprctl activewindow -j | jq -r '.address')\" opaque toggle")

    -- ─── Notifications ───
    o.bind("SUPER + comma", "Dismiss last notification", "omarchy-shell notifications dismissOne")
    o.bind("SUPER + SHIFT + comma", "Dismiss all notifications", "omarchy-shell notifications dismissAll")
    o.bind("SUPER + CTRL + comma", "Toggle notification silencing", "omarchy-toggle-notification-silencing")
    o.bind("SUPER + ALT + comma", "Invoke last notification", "omarchy-shell notifications invokeLast")
    -- The v4 shell IPC has no "restore last" — history is the closest verb.
    o.bind("SUPER + SHIFT + ALT + comma", "Notification history", "omarchy-shell notifications showHistory")

    -- ─── Toggle Idling ───
    o.bind("SUPER + CTRL + I", "Toggle idle locking", "omarchy-toggle-idle")

    -- ─── Nightlight ───
    o.bind("SUPER + CTRL + N", "Toggle nightlight", "omarchy-toggle-nightlight")

    -- ─── Screenshots ───
    o.bind("PRINT", "Screenshot with editing", "grim -g \"$(slurp)\" - | swappy -f -")
    o.bind("SHIFT + PRINT", "Screenshot to clipboard", "grim -g \"$(slurp)\" - | wl-copy")
    o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")

    -- ─── Battery ───
    o.bind("SUPER + SHIFT + Y", "Show battery status", "omarchy-notification-battery")

    -- ─── Window Gaps ───
    o.bind("SUPER + ALT + Z", "Toggle window gaps", "toggle-gaps")

    -- ─── Layout Toggle ───
    o.bind("SUPER + CTRL + M", "Toggle layout dwindle/master", "toggle-layout")

    -- ─── Screenshot OCR ───
    o.bind("SUPER + CTRL + PRINT", "Screenshot OCR", "screenshot-ocr")

    -- ─── Lock Screen ───
    -- Lock goes through the shell's ext-session-lock plugin
    -- (omarchy-shell lock lock); the v3 hyprlock-guard crash-supervision and
    -- logind LockedHint concerns are re-validated at sakura deploy
    -- (ADR-0004/0006 gates).
    o.bind("SUPER + CTRL + L", "Lock system", "omarchy-system-lock")

    -- ─── Control Panels ───
    o.bind("SUPER + CTRL + A", "Audio controls", "uwsm app -- pavucontrol")
    o.bind("SUPER + CTRL + B", "Bluetooth controls", "uwsm app -- blueman-manager")
    o.bind("SUPER + CTRL + W", "Wifi controls", "launch-wifi")
    o.bind("SUPER + CTRL + T", "Activity", "uwsm app -- alacritty -e btop")

    -- ─── Additional App Launchers ───
    o.bind("SUPER + SHIFT + RETURN", "Browser", "google-chrome")
    o.bind("SUPER + ALT + SHIFT + F", "File manager (current directory)", "file-manager-cwd")

    -- ─── Window Management (extended) ───
    o.bind("CTRL + ALT + DELETE", "Close all windows", "close-all-windows")
    o.bind("CTRL + ALT + TAB", "Cycle monitors", "cycle-monitors")
    o.bind("SUPER + slash", "Cycle monitor scaling", "cycle-monitor-scaling")

    -- ─── Menus (extended) ───
    o.bind("SUPER + CTRL + C", "Capture menu", "menu-capture")
    o.bind("SUPER + CTRL + O", "Toggle menu", "menu-toggle")
    o.bind("SUPER + CTRL + H", "Hardware menu", "menu-hardware")
    o.bind("SUPER + ALT + SPACE", "Kebun menu", "menu-omarchy")
    o.bind("SUPER + CTRL + SPACE", "Background menu", "menu-background")

    o.bind("XF86Calculator", "Calculator", "uwsm app -- gnome-calculator")

    -- ─── Aesthetics (extended) ───
    o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "toggle-gaps")
    o.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square", "toggle-single-window-square")

    -- ─── Toggles (extended) ───
    o.bind("SUPER + CTRL + DELETE", "Toggle laptop display", "toggle-laptop-display")
    o.bind("SUPER + CTRL + ALT + DELETE", "Toggle display mirroring", "toggle-mirror-display")

    -- ─── Captures (extended) ───
    o.bind("ALT + PRINT", "Screen recording menu", "screenrecord-menu")

    -- ─── Sharing ───
    o.bind("SUPER + CTRL + S", "Share (LocalSend)", "localsend-share")
    o.bind("SUPER + CTRL + period", "Transcode", "transcode")

    -- ─── Reminders ───
    o.bind("SUPER + CTRL + R", "Set reminder", "reminder-set")
    o.bind("SUPER + CTRL + ALT + R", "Show reminders", "reminder-show")
    o.bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "reminder-clear")

    -- ─── Info Displays ───
    o.bind("SUPER + CTRL + ALT + T", "Show time", "show-time")
    o.bind("SUPER + CTRL + ALT + B", "Show battery", "show-battery")
    o.bind("SUPER + CTRL + ALT + W", "Show weather", "show-weather")

    -- ─── Dictation ───
    o.bind("SUPER + CTRL + X", "Toggle dictation", "dictation-toggle")

    -- ─── Cursor Zoom ───
    o.bind("SUPER + CTRL + Z", "Zoom cursor in", "cursor-zoom")
    o.bind("SUPER + CTRL + ALT + Z", "Reset cursor zoom", "cursor-zoom-reset")

    -- ─── Non-menu binds ───
    -- nil description keeps these out of the keybinding menu, exactly like the
    -- old plain bind/bindr/bindl/bindm entries.

    -- Clipboard sends to the focused surface.
    o.bind("SUPER + C", nil, send_shortcut_once("CTRL", "Insert"))
    o.bind("SUPER + V", nil, send_shortcut_once("SHIFT", "Insert"))
    o.bind("SUPER + X", nil, send_shortcut_once("CTRL", "X"))

    -- Dictation push-to-talk.
    o.bind("F9", nil, "dictation-ptt")
    o.bind("F9", nil, "dictation-ptt-release", { release = true })

    -- Window drag/resize with the left/right mouse buttons.
    o.bind("SUPER + mouse:272", nil, hl.dsp.window.drag(), { mouse = true })
    o.bind("SUPER + mouse:273", nil, hl.dsp.window.resize(), { mouse = true })

    -- ─── Lid Switch ───
    --
    -- These are only safe because toggle-laptop-display now refuses to disable
    -- the last enabled output. Unguarded, this pair was the cause of the
    -- post-suspend hangs: lid close destroyed eDP-1's wl_output, and the
    -- matching lid-open handler could not undo it because it looked the panel
    -- up in `hyprctl monitors -j`, which omits disabled monitors. Suspend can
    -- also invert the ordering of the two — the close handler gets frozen and
    -- thaws on resume, after the open handler has already run — so the safety
    -- has to live in the script, not in the ordering here. See the comments on
    -- toggle-laptop-display in packages/scripts/default.nix.
    --
    -- They still earn their keep when docked: lidSwitchDocked = "ignore" means
    -- closing the lid with an external display attached does not suspend, and
    -- then switching the internal panel off is exactly right.
    o.bind("switch:on:Lid Switch", nil, "toggle-laptop-display off", { locked = true })
    o.bind("switch:off:Lid Switch", nil, "toggle-laptop-display on", { locked = true })
  '';

  xdg.configFile."hypr/windows.lua".text = ''
    -- Kebun window rules — ported verbatim from the old hyprland.conf
    -- windowrule/layerrule lists (ADR-0007 Stage 3). Some rules overlap with
    -- upstream defaults (suppress_event, the XWayland no_focus rule); kebun
    -- owns its values and the duplication is harmless.

    -- Suppress maximize events (Hyprland 0.53+).
    o.window(".*", { suppress_event = "maximize" })

    -- Default slight transparency (retuned for Hyprland 0.56, ADR-0007 Stage 1).
    o.window(".*", { opacity = "0.985 0.96" })

    -- Fix XWayland dragging issues.
    o.window({
      class = "^$",
      title = "^$",
      xwayland = true,
      float = true,
      fullscreen = false,
      pin = false,
    }, { no_focus = true })

    -- Bitwarden — no screen share, float.
    o.window("^(Bitwarden)$", { no_screen_share = true })
    o.window("^(Bitwarden)$", { tag = "+floating-window" })

    -- Browser tags.
    o.window("((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)", { tag = "+chromium-based-browser" })
    o.window("([fF]irefox|zen|librewolf)", { tag = "+firefox-based-browser" })
    o.window({ tag = "chromium-based-browser" }, { tile = true })
    o.window({ tag = "chromium-based-browser" }, { opacity = "1.0 0.985" })
    o.window({ tag = "firefox-based-browser" }, { opacity = "1.0 0.985" })

    -- Terminal tag.
    o.window("Alacritty", { tag = "+terminal" })

    -- TUI launchers — float, center, and size (inspired by Omarchy).
    o.window("^org\\.kebun\\..*$", { tag = "+kebun-tui" })
    o.window({ tag = "kebun-tui" }, { float = true })
    o.window({ tag = "kebun-tui" }, { center = true })
    o.window({ tag = "kebun-tui" }, { size = { 875, 600 } })

    -- Floating windows.
    o.window({ tag = "floating-window" }, { float = true })
    o.window({ tag = "floating-window" }, { center = true })
    o.window({ tag = "floating-window" }, { size = { 875, 600 } })

    -- Calculator.
    o.window("org.gnome.Calculator", { float = true })

    -- Media — no transparency.
    o.window("^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$", { opacity = "1 1" })

    -- Popped windows — rounding.
    o.window({ tag = "pop" }, { rounding = 8 })

    -- Idle inhibit on fullscreen.
    o.window(".*", { idle_inhibit = "fullscreen" })
  '';

  xdg.configFile."hypr/looknfeel.lua".text = ''
    -- Kebun look-and-feel — ported from the old hyprland.conf
    -- general/decoration/group/animations/dwindle/master/misc/cursor blocks
    -- (ADR-0007 Stage 3). Loads after default/hypr/looknfeel.lua, so these win
    -- per leaf key; upstream values kebun never set (e.g. the
    -- specialWorkspace animation, misc.disable_scale_notification) stay in
    -- effect. Border colors are plain strings — the HL.Gradient table form
    -- (colors + angle) is only needed for multi-stop gradients.

    hl.config({
      general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,

        col = {
          active_border = "rgb(56949f)",
          inactive_border = "rgba(595959aa)",
        },

        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
      },

      decoration = {
        rounding = 0,

        shadow = {
          enabled = true,
          range = 2,
          render_power = 3,
          color = "rgba(1a1a1aee)",
        },

        blur = {
          enabled = true,
          size = 2,
          passes = 2,
          special = true,
          brightness = 0.60,
          contrast = 0.75,
        },
      },

      group = {
        col = {
          border_active = "rgb(56949f)",
          border_inactive = "rgba(595959aa)",
        },

        groupbar = {
          font_size = 12,
          font_family = "monospace",
          font_weight_active = "ultraheavy",
          font_weight_inactive = "normal",
          indicator_height = 0,
          indicator_gap = 5,
          height = 22,
          gaps_in = 5,
          gaps_out = 0,
          text_color = "rgb(ffffff)",
          text_color_inactive = "rgba(ffffff90)",
          col = {
            active = "rgba(00000040)",
            inactive = "rgba(00000020)",
          },
          gradients = true,
          gradient_rounding = 0,
          gradient_round_only_edges = false,
        },
      },

      animations = {
        enabled = true,
      },
    })

    -- Bezier curves — kebun's old list, which happens to be identical to
    -- upstream's; re-declared so kebun owns it. Curve registration is
    -- re-entrant per reload (upstream re-runs looknfeel.lua on every reload).
    hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
    hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
    hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
    hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

    -- Animation list — kebun's values where they differ from upstream
    -- defaults (windows 4.79 vs upstream 3.79; workspaces disabled).
    hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
    hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
    hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
    hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
    hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
    hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
    hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
    hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
    hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
    hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
    hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
    hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
    hl.animation({ leaf = "workspaces", enabled = false })

    hl.config({
      dwindle = {
        preserve_split = true,
        force_split = 2,
      },

      master = {
        new_status = "master",
      },

      misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
        anr_missed_pings = 3,
        on_focus_under_fullscreen = 1,

        -- Rose Pine Dawn background (fallback when no wallpaper image).
        background_color = "rgb(250,244,237)",
      },

      cursor = {
        hide_on_key_press = true,
      },
    })
  '';

  xdg.configFile."hypr/autostart.lua".text = ''
    -- Kebun autostart — ported from the old exec-once list (ADR-0007 Stage 3),
    -- then swapped for the vendored Omarchy v4 QuickShell (ADR-0007 Stage 4):
    -- mako, waybar, walker and the polkit-gnome agent are gone; the shell now
    -- provides the bar, menus, OSD, notifications, lock and idle handling.
    -- Upstream's default.hypr.autostart is still not loaded by kebun's entry —
    -- kebun launches the shell itself below and skips the provisioning hooks.

    -- Slow app launch fix — set systemd vars before starting session services.
    o.exec_on_start("systemctl --user import-environment $(env | cut -d'=' -f 1)")
    o.exec_on_start("dbus-update-activation-environment --systemd --all")

    -- Session daemons. o.launch wraps with uwsm-app --, which is uwsm's own
    -- wrapper for `uwsm app --` — same systemd session scoping the old
    -- exec-once entries had.
    --
    -- The shell launch deliberately diverges from upstream: upstream's
    -- default/hypr/autostart.lua uses a raw hl.exec_cmd("omarchy-launch-shell"),
    -- but kebun's UWSM mandate requires every launched app to land inside the
    -- systemd session scope (see CLAUDE.md), so it gets an explicit
    -- `uwsm app --` prefix instead.
    o.exec_on_start("uwsm app -- omarchy-launch-shell")
    o.launch_on_start("fcitx5")
    -- Wallpaper stays swaybg (solid Rose Pine Dawn) until the Stage 5 theme
    -- engine lands.
    o.launch_on_start("swaybg -c '#faf4ed' -m solid_color")
  '';

  # ─── Idle handling ───
  # Idle is the shell's idle service plugin now; timings live in shell.json
  # (screensaver 150s, lock 300s). No idle-suspend: the v3 hypridle 900s
  # suspend listener is intentionally not carried — noted for deploy
  # validation on sakura.

  # ─── Lock screen ───
  # The shell's lock plugin is the lock screen now (omarchy-shell lock lock).
  # Its PAM service, omarchy-lock-password, is enabled system-side by the
  # Stage 4 desktop module.

  # ─── Notifications ───
  # The shell is the notification daemon now (omarchy-shell notifications …,
  # omarchy-notification-send); its silencing state lives in
  # ~/.local/state/omarchy/notifications.json.
}
