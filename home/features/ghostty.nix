{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;
in {
  programs.ghostty = {
    enable = true;

    settings = {
      # Rose Pine Dawn theme colors
      background = palette.background;
      foreground = palette.text;
      cursor-color = palette.cursor;
      selection-background = palette.highlightMed;
      selection-foreground = palette.text;

      # Normal colors
      palette = palette.ghosttyPalette;

      # Font
      font-family = "CaskaydiaMono Nerd Font";
      font-size = 12;

      # Window
      window-decoration = false;
      window-padding-x = 14;
      window-padding-y = 14;

      # Shell
      shell-integration = "fish";
      command = "${pkgs.fish}/bin/fish -l";

      # Misc
      confirm-close-surface = false;
      copy-on-select = true;
      clipboard-read = "allow";
      clipboard-write = "allow";
      clipboard-paste-protection = false;
      mouse-hide-while-typing = true;
      scrollback-limit = 10000000;
    };
  };
}
