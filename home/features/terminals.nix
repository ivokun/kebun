{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;

  # ANSI slot names, 0–7; bright colors reuse the same names at slots 8–15.
  ansiNames = ["black" "red" "green" "yellow" "blue" "magenta" "cyan" "white"];
  ansiColors = offset:
    lib.listToAttrs (lib.imap0 (
        i: name: lib.nameValuePair name (builtins.elemAt palette.ansi (i + offset))
      )
      ansiNames);
in {
  # ─── Alacritty (Primary Terminal) ───
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      font = {
        normal = {
          family = "CaskaydiaMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "CaskaydiaMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "CaskaydiaMono Nerd Font";
          style = "Italic";
        };
        size = 12.5;
      };

      window = {
        padding = {
          x = 5;
          y = 5;
        };
        decorations = "None";
      };

      keyboard.bindings = [
        {
          key = "F11";
          action = "ToggleFullscreen";
        }
      ];

      terminal.shell = {
        program = "${pkgs.fish}/bin/fish";
        args = ["-l"];
      };

      # Rose Pine Dawn colors
      colors = {
        primary = {
          background = palette.background;
          foreground = palette.text;
        };

        cursor = {
          text = palette.background;
          cursor = palette.cursor;
        };

        "vi_mode_cursor" = {
          text = palette.background;
          cursor = palette.cursor;
        };

        search.matches = {
          foreground = palette.background;
          background = palette.gold;
        };

        search."focused_match" = {
          foreground = palette.background;
          background = palette.love;
        };

        "footer_bar" = {
          foreground = palette.background;
          background = palette.text;
        };

        selection = {
          text = palette.text;
          background = palette.highlightMed;
        };

        normal = ansiColors 0;
        bright = ansiColors 8;
      };
    };
  };
}
