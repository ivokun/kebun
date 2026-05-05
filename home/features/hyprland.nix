{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  # Rose Pine Dawn active border color
  activeBorderColor = "rgb(56949f)";
  inactiveBorderColor = "rgba(595959aa)";

  # Rose Pine Dawn background color (fallback when no wallpaper image)
  bgColor = "rgb(250,244,237)";
in {
  # ─── Hyprland Configuration ───
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    systemd = {
      enable = true;
      variables = ["--all"];
    };

    settings = {
      # ─── Monitors ───
      # Using auto-detect with scale 1 to match current Arch/Omarchy setup
      monitor = [
        ",preferred,auto,1"
      ];

      # ─── Environment Variables ───
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "GDK_BACKEND,wayland,x11,*"
        "QT_QPA_PLATFORM,wayland;xcb"
        "QT_STYLE_OVERRIDE,kvantum"
        "SDL_VIDEODRIVER,wayland"
        "MOZ_ENABLE_WAYLAND,1"
        "ELECTRON_OZONE_PLATFORM_HINT,wayland"
        "OZONE_PLATFORM,wayland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "GDK_SCALE,1"
        "TERMINAL,alacritty"

        # Japanese input method (fcitx5-mozc)
        "GTK_IM_MODULE,fcitx"
        "QT_IM_MODULE,fcitx"
        "XMODIFIERS,@im=fcitx"
      ];

      # ─── XWayland ───
      xwayland.force_zero_scaling = true;

      # ─── Ecosystem ───
      ecosystem.no_update_news = true;

      # ─── Input ───
      input = {
        kb_layout = "us";
        kb_options = "compose:caps";
        follow_mouse = 1;
        sensitivity = 0;
        repeat_rate = 40;
        repeat_delay = 600;
        numlock_by_default = true;

        touchpad = {
          natural_scroll = true;
          scroll_factor = 0.4;
          disable_while_typing = true;
          tap-to-click = true;
          drag_lock = false;
          middle_button_emulation = true;
        };
      };

      # ─── General ───
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = activeBorderColor;
        "col.inactive_border" = inactiveBorderColor;
        resize_on_border = false;
        allow_tearing = false;
        layout = "dwindle";
      };

      # ─── Decoration ───
      decoration = {
        rounding = 0;

        shadow = {
          enabled = true;
          range = 2;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;
          size = 2;
          passes = 2;
          special = true;
          brightness = 0.60;
          contrast = 0.75;
        };
      };

      # ─── Group ───
      group = {
        "col.border_active" = activeBorderColor;
        "col.border_inactive" = inactiveBorderColor;

        groupbar = {
          font_size = 12;
          font_family = "monospace";
          font_weight_active = "ultraheavy";
          font_weight_inactive = "normal";
          indicator_height = 0;
          indicator_gap = 5;
          height = 22;
          gaps_in = 5;
          gaps_out = 0;
          text_color = "rgb(ffffff)";
          text_color_inactive = "rgba(ffffff90)";
          "col.active" = "rgba(00000040)";
          "col.inactive" = "rgba(00000020)";
          gradients = true;
          gradient_rounding = 0;
          gradient_round_only_edges = false;
        };
      };

      # ─── Animations ───
      animations = {
        enabled = true;

        bezier = [
          "easeOutQuint,0.23,1,0.32,1"
          "easeInOutCubic,0.65,0.05,0.36,1"
          "linear,0,0,1,1"
          "almostLinear,0.5,0.5,0.75,1.0"
          "quick,0.15,0,0.1,1"
        ];

        animation = [
          "global, 1, 10, default"
          "border, 1, 5.39, easeOutQuint"
          "windows, 1, 4.79, easeOutQuint"
          "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
          "windowsOut, 1, 1.49, linear, popin 87%"
          "fadeIn, 1, 1.73, almostLinear"
          "fadeOut, 1, 1.46, almostLinear"
          "fade, 1, 3.03, quick"
          "layers, 1, 3.81, easeOutQuint"
          "layersIn, 1, 4, easeOutQuint, fade"
          "layersOut, 1, 1.5, linear, fade"
          "fadeLayersIn, 1, 1.79, almostLinear"
          "fadeLayersOut, 1, 1.39, almostLinear"
          "workspaces, 0, 0, ease"
        ];
      };

      # ─── Dwindle Layout ───
      dwindle = {
        preserve_split = true;
        force_split = 2;
      };

      # ─── Master Layout ───
      master.new_status = "master";

      # ─── Misc ───
      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        focus_on_activate = true;
        anr_missed_pings = 3;
        on_focus_under_fullscreen = 1;
        background_color = bgColor;
      };

      # ─── Cursor ───
      cursor.hide_on_key_press = true;

      # ─── Window Rules ───
      windowrule = [
        # Suppress maximize events (Hyprland 0.53+)
        "suppress_event maximize, match:class .*"

        # Default slight transparency
        "opacity 0.97 0.9, match:class .*"

        # Fix XWayland dragging issues
        "no_focus on, match:class ^$, match:title ^$, match:xwayland 1, match:float 1, match:fullscreen 0, match:pin 0"

        # Bitwarden — no screen share, float
        "no_screen_share on, match:class ^(Bitwarden)$"
        "tag +floating-window, match:class ^(Bitwarden)$"

        # Browser tags
        "tag +chromium-based-browser, match:class ((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)"
        "tag +firefox-based-browser, match:class ([fF]irefox|zen|librewolf)"
        "tile on, match:tag chromium-based-browser"
        "opacity 1 0.97, match:tag chromium-based-browser"
        "opacity 1 0.97, match:tag firefox-based-browser"

        # Terminal tag
        "tag +terminal, match:class Alacritty"

        # Floating windows
        "float on, match:tag floating-window"
        "center on, match:tag floating-window"
        "size 875 600, match:tag floating-window"

        # Calculator
        "float on, match:class org.gnome.Calculator"

        # Media — no transparency
        "opacity 1 1, match:class ^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$"

        # Popped windows — rounding
        "rounding 8, match:tag pop"

        # Idle inhibit on fullscreen
        "idle_inhibit fullscreen, match:class .*"
      ];

      # ─── Layer Rules ───
      layerrule = [
        "no_anim on, match:namespace walker"
      ];

      # ─── Keybindings ───
      "$terminal" = "uwsm app -- $TERMINAL";
      "$browser" = "google-chrome";

      bindd = [
        # ─── Application Launchers ───
        "SUPER, RETURN, Terminal, exec, $terminal --working-directory=\"$(${pkgs.zoxide}/bin/zoxide query --interactive || pwd)\""
        "SUPER SHIFT, F, File manager, exec, uwsm app -- nautilus --new-window"
        "SUPER, B, Browser, exec, $browser"
        "SUPER SHIFT, B, Browser (private), exec, $browser --private"
        "SUPER, N, Editor, exec, uwsm app -- nvim"
        "SUPER, D, Docker, exec, uwsm app -- ${pkgs.alacritty}/bin/alacritty -e lazydocker"
        "SUPER, O, Obsidian, exec, uwsm app -- obsidian -disable-gpu --enable-wayland-ime"

        # ─── Menus ───
        "SUPER, SPACE, Launch apps, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        "SUPER CTRL, E, Emoji picker, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker -m symbols"
        "SUPER CTRL, SPACE, System menu, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        "SUPER, ESCAPE, System menu, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        ", XF86PowerOff, Power menu, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker"
        "SUPER, K, Show keybindings, exec, ${pkgs.hyprland}/bin/hyprctl bindlist"

        # ─── Window Management ───
        "SUPER, W, Close window, killactive,"
        "SUPER, J, Toggle window split, layoutmsg, togglesplit"
        "SUPER, P, Pseudo window, pseudo,"
        "SUPER, T, Toggle window floating/tiling, togglefloating,"
        "SUPER, F, Full screen, fullscreen, 0"
        "SUPER CTRL, F, Tiled full screen, fullscreenstate, 0 2"
        "SUPER ALT, F, Full width, fullscreen, 1"
        "SUPER, O, Pop window, exec, window-pop"
        "SUPER, L, Toggle workspace layout, exec, ${pkgs.hyprland}/bin/hyprctl dispatch layoutmsg, orientationnext"

        # ─── Focus Movement ───
        "SUPER, LEFT, Move window focus left, movefocus, l"
        "SUPER, RIGHT, Move window focus right, movefocus, r"
        "SUPER, UP, Move window focus up, movefocus, u"
        "SUPER, DOWN, Move window focus down, movefocus, d"

        # ─── Workspace Switching ───
        "SUPER, code:10, Switch to workspace 1, workspace, 1"
        "SUPER, code:11, Switch to workspace 2, workspace, 2"
        "SUPER, code:12, Switch to workspace 3, workspace, 3"
        "SUPER, code:13, Switch to workspace 4, workspace, 4"
        "SUPER, code:14, Switch to workspace 5, workspace, 5"
        "SUPER, code:15, Switch to workspace 6, workspace, 6"
        "SUPER, code:16, Switch to workspace 7, workspace, 7"
        "SUPER, code:17, Switch to workspace 8, workspace, 8"
        "SUPER, code:18, Switch to workspace 9, workspace, 9"
        "SUPER, code:19, Switch to workspace 10, workspace, 10"

        # ─── Move Window to Workspace ───
        "SUPER SHIFT, code:10, Move window to workspace 1, movetoworkspace, 1"
        "SUPER SHIFT, code:11, Move window to workspace 2, movetoworkspace, 2"
        "SUPER SHIFT, code:12, Move window to workspace 3, movetoworkspace, 3"
        "SUPER SHIFT, code:13, Move window to workspace 4, movetoworkspace, 4"
        "SUPER SHIFT, code:14, Move window to workspace 5, movetoworkspace, 5"
        "SUPER SHIFT, code:15, Move window to workspace 6, movetoworkspace, 6"
        "SUPER SHIFT, code:16, Move window to workspace 7, movetoworkspace, 7"
        "SUPER SHIFT, code:17, Move window to workspace 8, movetoworkspace, 8"
        "SUPER SHIFT, code:18, Move window to workspace 9, movetoworkspace, 9"
        "SUPER SHIFT, code:19, Move window to workspace 10, movetoworkspace, 10"

        # ─── Move Window Silently ───
        "SUPER SHIFT ALT, code:10, Move window silently to workspace 1, movetoworkspacesilent, 1"
        "SUPER SHIFT ALT, code:11, Move window silently to workspace 2, movetoworkspacesilent, 2"
        "SUPER SHIFT ALT, code:12, Move window silently to workspace 3, movetoworkspacesilent, 3"
        "SUPER SHIFT ALT, code:13, Move window silently to workspace 4, movetoworkspacesilent, 4"
        "SUPER SHIFT ALT, code:14, Move window silently to workspace 5, movetoworkspacesilent, 5"
        "SUPER SHIFT ALT, code:15, Move window silently to workspace 6, movetoworkspacesilent, 6"
        "SUPER SHIFT ALT, code:16, Move window silently to workspace 7, movetoworkspacesilent, 7"
        "SUPER SHIFT ALT, code:17, Move window silently to workspace 8, movetoworkspacesilent, 8"
        "SUPER SHIFT ALT, code:18, Move window silently to workspace 9, movetoworkspacesilent, 9"
        "SUPER SHIFT ALT, code:19, Move window silently to workspace 10, movetoworkspacesilent, 10"

        # ─── Scratchpad ───
        "SUPER, S, Toggle scratchpad, togglespecialworkspace, scratchpad"
        "SUPER ALT, S, Move window to scratchpad, movetoworkspacesilent, special:scratchpad"

        # ─── Workspace Cycling ───
        "SUPER, TAB, Next workspace, workspace, e+1"
        "SUPER SHIFT, TAB, Previous workspace, workspace, e-1"
        "SUPER CTRL, TAB, Former workspace, workspace, previous"

        # ─── Move Workspace to Monitor ───
        "SUPER SHIFT ALT, LEFT, Move workspace to left monitor, movecurrentworkspacetomonitor, l"
        "SUPER SHIFT ALT, RIGHT, Move workspace to right monitor, movecurrentworkspacetomonitor, r"
        "SUPER SHIFT ALT, UP, Move workspace to up monitor, movecurrentworkspacetomonitor, u"
        "SUPER SHIFT ALT, DOWN, Move workspace to down monitor, movecurrentworkspacetomonitor, d"

        # ─── Swap Windows ───
        "SUPER SHIFT, LEFT, Swap window to the left, swapwindow, l"
        "SUPER SHIFT, RIGHT, Swap window to the right, swapwindow, r"
        "SUPER SHIFT, UP, Swap window up, swapwindow, u"
        "SUPER SHIFT, DOWN, Swap window down, swapwindow, d"

        # ─── Cycle Windows ───
        "ALT, TAB, Cycle to next window, cyclenext,"
        "ALT SHIFT, TAB, Cycle to prev window, cyclenext, prev"

        # ─── Resize ───
        "SUPER, code:20, Expand window left, resizeactive, -100 0"
        "SUPER, code:21, Shrink window left, resizeactive, 100 0"
        "SUPER SHIFT, code:20, Shrink window up, resizeactive, 0 -100"
        "SUPER SHIFT, code:21, Expand window down, resizeactive, 0 100"

        # ─── Groups ───
        "SUPER, G, Toggle window grouping, togglegroup,"
        "SUPER ALT, G, Move active window out of group, moveoutofgroup,"
        "SUPER ALT, LEFT, Move window to group on left, moveintogroup, l"
        "SUPER ALT, RIGHT, Move window to group on right, moveintogroup, r"
        "SUPER ALT, UP, Move window to group on top, moveintogroup, u"
        "SUPER ALT, DOWN, Move window to group on bottom, moveintogroup, d"
        "SUPER ALT, TAB, Next window in group, changegroupactive, f"
        "SUPER ALT SHIFT, TAB, Previous window in group, changegroupactive, b"
        "SUPER CTRL, LEFT, Move grouped window focus left, changegroupactive, b"
        "SUPER CTRL, RIGHT, Move grouped window focus right, changegroupactive, f"

        # ─── Clipboard ───
        
        "SUPER CTRL, V, Clipboard manager, exec, ${inputs.walker.packages.${pkgs.system}.walker}/bin/walker -m clipboard"

        # ─── Mouse Bindings ───
        "SUPER, mouse_down, Scroll workspace forward, workspace, e+1"
        "SUPER, mouse_up, Scroll workspace backward, workspace, e-1"

        # ─── Media Keys ───
        ", XF86AudioRaiseVolume, Volume up, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, Volume down, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, Mute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioMicMute, Mute microphone, exec, swayosd-client --input-volume mute-toggle"
        ", XF86MonBrightnessUp, Brightness up, exec, swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, Brightness down, exec, swayosd-client --brightness lower"

        # ─── Precise Media Adjustments ───
        "ALT, XF86AudioRaiseVolume, Volume up precise, exec, swayosd-client --output-volume +1"
        "ALT, XF86AudioLowerVolume, Volume down precise, exec, swayosd-client --output-volume -1"
        "ALT, XF86MonBrightnessUp, Brightness up precise, exec, swayosd-client --brightness +1"
        "ALT, XF86MonBrightnessDown, Brightness down precise, exec, swayosd-client --brightness -1"

        # ─── Media Playback ───
        ", XF86AudioNext, Next track, exec, ${pkgs.playerctl}/bin/playerctl next"
        ", XF86AudioPause, Pause, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
        ", XF86AudioPlay, Play, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
        ", XF86AudioPrev, Previous track, exec, ${pkgs.playerctl}/bin/playerctl previous"

        # ─── Audio Output Switch ───
        "SUPER, XF86AudioMute, Switch audio output, exec, ${pkgs.pamixer}/bin/pamixer --default-source toggle"

        # ─── Aesthetics ───
        "SUPER SHIFT, SPACE, Toggle top bar, exec, toggle-waybar"
        "SUPER, BACKSPACE, Toggle window transparency, exec, ${pkgs.hyprland}/bin/hyprctl dispatch setprop \"address:$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.address')\" opaque toggle"

        # ─── Notifications ───
        "SUPER, COMMA, Dismiss last notification, exec, ${pkgs.mako}/bin/makoctl dismiss"
        "SUPER SHIFT, COMMA, Dismiss all notifications, exec, ${pkgs.mako}/bin/makoctl dismiss --all"
        "SUPER CTRL, COMMA, Toggle DND, exec, ${pkgs.mako}/bin/makoctl mode -t do-not-disturb && ${pkgs.libnotify}/bin/notify-send 'Notifications silenced' || ${pkgs.libnotify}/bin/notify-send 'Notifications enabled'"
        "SUPER ALT, COMMA, Invoke last notification, exec, ${pkgs.mako}/bin/makoctl invoke"
        "SUPER SHIFT ALT, COMMA, Restore last notification, exec, ${pkgs.mako}/bin/makoctl restore"

        # ─── Toggle Idling ───
        "SUPER CTRL, I, Toggle locking on idle, exec, ${pkgs.hypridle}/bin/hypridle --toggle"

        # ─── Nightlight ───
        "SUPER CTRL, N, Toggle nightlight, exec, toggle-nightlight"

        # ─── Screenshots ───
        ", PRINT, Screenshot with editing, exec, ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.swappy}/bin/swappy -f -"
        "SHIFT, PRINT, Screenshot to clipboard, exec, ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
        "SUPER, PRINT, Color picker, exec, ${pkgs.procps}/bin/pkill hyprpicker || ${pkgs.hyprpicker}/bin/hyprpicker -a"

        # ─── Lock Screen ───
        "SUPER CTRL, L, Lock system, exec, ${pkgs.hyprlock}/bin/hyprlock"

        # ─── Control Panels ───
        "SUPER CTRL, A, Audio controls, exec, uwsm app -- ${pkgs.pavucontrol}/bin/pavucontrol"
        "SUPER CTRL, B, Bluetooth controls, exec, uwsm app -- ${pkgs.blueman}/bin/blueman-manager"
        "SUPER CTRL, W, Wifi controls, exec, uwsm app -- ${pkgs.networkmanagerapplet}/bin/nm-connection-editor"
        "SUPER CTRL, T, Activity, exec, uwsm app -- ${pkgs.alacritty}/bin/alacritty -e btop"
      ];

      bind = [
        "SUPER, C, sendshortcut, CTRL Insert"
        "SUPER, V, sendshortcut, SHIFT Insert"
        "SUPER, X, sendshortcut, CTRL X"
      ];

      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
      ];

      # ─── Exec-once (Autostart) ───
      exec-once = [
        "uwsm app -- mako"
        "uwsm app -- mako"
        "uwsm app -- waybar"
        "uwsm app -- fcitx5"
        "uwsm app -- swaybg -c '#faf4ed' -m solid_color"
        "uwsm app -- swayosd-server"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "systemctl --user import-environment $(env | cut -d'=' -f 1)"
        "dbus-update-activation-environment --systemd --all"
      ];
    };
  };

  # ─── Hypridle ───
  services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "${pkgs.hyprlock}/bin/hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          inhibit_sleep = 3;
        };

        listener = [
          {
            timeout = 600;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 605;
            on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
            on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on && ${pkgs.brightnessctl}/bin/brightnessctl -r";
          }
          {
            timeout = 900;
            on-timeout = "systemctl suspend";
          }
        ];
      };
    };

  # ─── Hyprlock ───
  programs.hyprlock = {
    enable = true;

    settings = {
      general.ignore_empty_input = true;

      background = {
        monitor = "";
        color = "rgba(250,244,237, 1.0)";
        blur_passes = 3;
      };

      animations.enabled = false;

      input-field = {
        monitor = "";
        size = "650, 100";
        position = "0, 0";
        halign = "center";
        valign = "center";
        inner_color = "rgba(250,244,237, 0.8)";
        outer_color = "rgba(87,82,121, 1.0)";
        outline_thickness = 4;
        font_family = "CaskaydiaMono Nerd Font";
        font_color = "rgba(87,82,121, 1.0)";
        placeholder_text = "Enter Password";
        check_color = "rgba(86,148,159, 1.0)";
        fail_text = "<i>$FAIL ($ATTEMPTS)</i>";
        rounding = 0;
        shadow_passes = 0;
        fade_on_empty = false;
      };

      # Fingerprint auth (ThinkPad X13 Gen 1)
      auth = {
        fingerprint.enabled = true;
      };
    };
  };

  # ─── Hyprsunset ───
  services.hyprsunset = {
    enable = true;
  };

  # ─── Mako (Notifications) ───
  services.mako = {
    enable = true;

    settings = {
      anchor = "top-right";
      default-timeout = 5000;
      width = 420;
      "outer-margin" = 20;
      padding = "10,15";
      "border-size" = 2;
      "max-icon-size" = 32;
      font = "sans-serif 14px";

      "urgency=critical" = {
        default-timeout = 0;
        layer = "overlay";
      };

      "mode=do-not-disturb" = {
        invisible = true;
      };
    };

    # Rose Pine Dawn colors
    extraConfig = ''
      text-color=#575279
      border-color=#56949f
      background-color=#faf4ed
    '';
  };
}
