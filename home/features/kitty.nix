{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.kitty = {
    enable = true;

    settings = {
      # Rose Pine Dawn colors
      background = "#faf4ed";
      foreground = "#575279";
      cursor = "#cecacd";
      cursor_text_color = "#faf4ed";
      selection_background = "#dfdad9";
      selection_foreground = "#575279";
      url_color = "#56949f";

      # Normal colors
      color0 = "#f2e9e1";
      color1 = "#b4637a";
      color2 = "#286983";
      color3 = "#ea9d34";
      color4 = "#56949f";
      color5 = "#907aa9";
      color6 = "#d7827e";
      color7 = "#575279";

      # Bright colors
      color8 = "#9893a5";
      color9 = "#b4637a";
      color10 = "#286983";
      color11 = "#ea9d34";
      color12 = "#56949f";
      color13 = "#907aa9";
      color14 = "#d7827e";
      color15 = "#575279";

      # Font
      font_family = "CaskaydiaMono Nerd Font";
      font_size = 12;
      disable_ligatures = "never";

      # Window
      hide_window_decorations = true;
      window_padding_width = 14;
      background_opacity = "0.97";

      # Shell
      shell = "${pkgs.fish}/bin/fish -l";

      # Scrollback
      scrollback_lines = 100000;
      scrollback_pager = "less +G -R";

      # Tab bar
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      active_tab_background = "#56949f";
      active_tab_foreground = "#faf4ed";
      inactive_tab_background = "#f2e9e1";
      inactive_tab_foreground = "#575279";

      # Cursor
      cursor_shape = "block";
      cursor_blink_interval = 0;

      # Misc
      enable_audio_bell = false;
      visual_bell_duration = 0.0;
      confirm_os_window_close = 0;
      copy_on_select = true;
      strip_trailing_spaces = "smart";
    };

    keybindings = {
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+w" = "close_tab";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+left" = "previous_tab";
      "ctrl+shift+enter" = "new_window";
      "ctrl+shift+n" = "new_os_window";
      "ctrl+shift+f" = "show_scrollback";
      "ctrl+shift+equal" = "increase_font_size";
      "ctrl+shift+minus" = "decrease_font_size";
      "ctrl+shift+0" = "restore_font_size";
      "f11" = "toggle_fullscreen";
    };
  };
}
