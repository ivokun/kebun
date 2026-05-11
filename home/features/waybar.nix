{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
  programs.waybar = {
    enable = true;

    settings = {
      mainBar = {
        reload_style_on_change = true;
        layer = "top";
        position = "top";
        spacing = 0;
        height = 26;

        modules-left = ["hyprland/workspaces"];
        modules-center = ["clock"];
        modules-right = [
          "custom/updates"
          "custom/screenrecording"
          "custom/idle"
          "custom/notification-silencing"
          "group/tray-expander"
          "bluetooth"
          "network"
          "pulseaudio"
          "battery"
          "custom/power"
          "cpu"
        ];

        "hyprland/workspaces" = {
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            default = "";
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            "7" = "7";
            "8" = "8";
            "9" = "9";
            "10" = "0";
            active = "󱓻";
          };
          persistent-workspaces = {
            "1" = [];
            "2" = [];
            "3" = [];
            "4" = [];
            "5" = [];
          };
        };

        cpu = {
          interval = 5;
          format = "󰍛";
          on-click = "launch-activity";
        };

        clock = {
          format = "{:L%A %H:%M}";
          "format-alt" = "{:L%d %B W%V %Y}";
          tooltip = false;
        };

        network = {
          format-icons = ["󰤯" "󰤟" "󰤢" "󰤥" "󰤨"];
          format = "{icon}";
          "format-wifi" = "{icon}";
          "format-ethernet" = "󰀂";
          "format-disconnected" = "󰤮";
          "tooltip-format-wifi" = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
          "tooltip-format-ethernet" = "⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
          "tooltip-format-disconnected" = "Disconnected";
          interval = 3;
          spacing = 1;
          on-click = "launch-wifi";
        };

        bluetooth = {
          format = "";
          "format-disabled" = "󰂲";
          "format-off" = "󰂲";
          "format-connected" = "󰂱";
          "format-no-controller" = "";
          "tooltip-format" = "Devices connected: {num_connections}";
          on-click = "launch-bluetooth";
        };

        pulseaudio = {
          format = "{icon}";
          "format-muted" = "";
          "format-icons" = {
            headphone = "";
            default = ["" "" ""];
          };
          "tooltip-format" = "Playing at {volume}%";
          "scroll-step" = 5;
          "on-click" = "launch-audio";
          "on-click-right" = "${pkgs.pamixer}/bin/pamixer -t";
        };

        battery = {
          interval = 30;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          "format-full" = "󰁹";
          "format-charging" = "󰂄";
          "format-icons" = ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰂃"];
          "tooltip-format" = "{capacity}% ({timeTo})";
        };

        "group/tray-expander" = {
          orientation = "inherit";
          drawer = {
            "transition-duration" = 600;
            "children-class" = "tray-group-item";
          };
          modules = ["custom/expand-icon" "tray"];
        };

        "custom/expand-icon" = {
          format = " ";
          tooltip = false;
        };

        tray = {
          "icon-size" = 12;
          spacing = 12;
        };

        "custom/screenrecording" = {
          exec = "echo ''";
          interval = 2;
          return-type = "json";
          format = "{}";
          exec-if = "pgrep -x wl-screenrec";
          format-icons = {
            "recording" = " ";
          };
          tooltip = true;
          "tooltip-format" = "Screen recording active";
          class = "screenrecording";
        };

        "custom/idle" = {
          exec = "echo ''";
          interval = 2;
          return-type = "json";
          format = "{}";
          exec-if = "test -f /tmp/hypridle-disabled";
          format-icons = {
            "disabled" = "󰈈 ";
          };
          tooltip = true;
          "tooltip-format" = "Idle lock disabled";
          class = "idle-disabled";
        };

        "custom/notification-silencing" = {
          exec = "echo ''";
          interval = 2;
          return-type = "json";
          format = "{}";
          exec-if = "makoctl mode | grep -q do-not-disturb";
          format-icons = {
            "dnd" = "󰂛 ";
          };
          tooltip = true;
          "tooltip-format" = "Do not disturb";
          class = "dnd";
        };

        "custom/updates" = {
          exec = "check-waybar-updates";
          interval = 3600;
          return-type = "json";
          format = "{}";
          format-icons = {
            "updates" = "󰏗 ";
          };
          tooltip = true;
          "tooltip-format" = "NixOS flake updates available";
          "on-click" = "launch-tui check-updates";
          class = "updates";
        };

        "custom/power" = {
          format = "{}";
          exec = "powerprofilesctl get 2>/dev/null || echo 'unknown'";
          interval = 5;
          tooltip = true;
          on-click = "toggle-power-profile";
        };
      };
    };

    # Rose Pine Dawn themed CSS
    style = ''
      @define-color foreground #575279;
      @define-color background #faf4ed;

      * {
        background-color: @background;
        color: @foreground;
        border: none;
        border-radius: 0;
        min-height: 0;
        font-family: 'CaskaydiaMono Nerd Font';
        font-size: 12px;
      }

      .modules-left {
        margin-left: 8px;
      }

      .modules-right {
        margin-right: 8px;
      }

      #workspaces button {
        all: initial;
        padding: 0 6px;
        margin: 0 1.5px;
        min-width: 9px;
      }

      #workspaces button.empty {
        opacity: 0.5;
      }

      #cpu,
      #pulseaudio,
      #battery,
      #custom-expand-icon {
        min-width: 12px;
        margin: 0 7.5px;
      }

      #battery.warning {
        color: #ea9d34;
      }

      #battery.critical {
        color: #b4637a;
      }

      #tray {
        margin-right: 16px;
      }

      #bluetooth {
        margin-right: 17px;
      }

      #network {
        margin-right: 13px;
      }

      tooltip {
        padding: 2px;
      }

      #clock {
        margin-left: 5px;
      }

      #custom-screenrecording {
        color: #b4637a;
        margin-right: 10px;
      }

      #custom-idle {
        color: #ea9d34;
        margin-right: 10px;
      }

      #custom-notification-silencing {
        color: #907aa9;
        margin-right: 10px;
      }

      #custom-updates {
        color: #286983;
        margin-right: 10px;
      }

      #custom-power {
        min-width: 12px;
        margin: 0 7.5px;
      }

      .hidden {
        opacity: 0;
      }
    '';
  };
}
