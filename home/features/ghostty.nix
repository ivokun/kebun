{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.ghostty = {
    enable = true;

    settings = {
      # Rose Pine Dawn theme colors
      background = "#faf4ed";
      foreground = "#575279";
      cursor-color = "#cecacd";
      selection-background = "#dfdad9";
      selection-foreground = "#575279";

      # Normal colors
      palette = [
        "0=#f2e9e1"
        "1=#b4637a"
        "2=#286983"
        "3=#ea9d34"
        "4=#56949f"
        "5=#907aa9"
        "6=#d7827e"
        "7=#575279"
        "8=#9893a5"
        "9=#b4637a"
        "10=#286983"
        "11=#ea9d34"
        "12=#56949f"
        "13=#907aa9"
        "14=#d7827e"
        "15=#575279"
      ];

      # Font
      font-family = "CaskaydiaMono Nerd Font";
      font-size = 12;

      # Window
      window-decoration = false;
      window-padding-x = 14;
      window-padding-y = 14;

      # Shell
      shell-integration = "zsh";
      command = "${pkgs.zsh}/bin/zsh -l";

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
