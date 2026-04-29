{
  config,
  lib,
  pkgs,
  ...
}: {
  # ─── Alacritty (Primary Terminal) ───
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      font = {
        normal = {family = "CaskaydiaMono Nerd Font"; style = "Regular";};        bold = {family = "CaskaydiaMono Nerd Font"; style = "Bold";};        italic = {family = "CaskaydiaMono Nerd Font"; style = "Italic";};        size = 12.5;
      };

      window = {
        padding = {x = 5; y = 5;};
        decorations = "None";
      };

      keyboard.bindings = [
        {key = "F11"; action = "ToggleFullscreen";}
        {key = "Return"; mods = "Shift"; chars = "\u001b[13;2u";}
      ];

      terminal.shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = ["-l"];
      };

      # Rose Pine Dawn colors
      colors = {
        primary = {
          background = "#faf4ed";
          foreground = "#575279";
        };

        cursor = {
          text = "#faf4ed";
          cursor = "#cecacd";
        };

        "vi_mode_cursor" = {
          text = "#faf4ed";
          cursor = "#cecacd";
        };

        search.matches = {
          foreground = "#faf4ed";
          background = "#ea9d34";
        };

        search."focused_match" = {
          foreground = "#faf4ed";
          background = "#b4637a";
        };

        "footer_bar" = {
          foreground = "#faf4ed";
          background = "#575279";
        };

        selection = {
          text = "#575279";
          background = "#dfdad9";
        };

        normal = {
          black = "#f2e9e1";
          red = "#b4637a";
          green = "#286983";
          yellow = "#ea9d34";
          blue = "#56949f";
          magenta = "#907aa9";
          cyan = "#d7827e";
          white = "#575279";
        };

        bright = {
          black = "#9893a5";
          red = "#b4637a";
          green = "#286983";
          yellow = "#ea9d34";
          blue = "#56949f";
          magenta = "#907aa9";
          cyan = "#d7827e";
          white = "#575279";
        };
      };
    };
  };
}
