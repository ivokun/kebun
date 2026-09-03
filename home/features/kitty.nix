{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;

  # ANSI slots 0–15 as kitty's color0..color15 keys.
  kittyAnsi = builtins.listToAttrs (
    lib.imap0 (i: c: lib.nameValuePair "color${toString i}" c) palette.ansi
  );
in {
  programs.kitty = {
    enable = true;

    settings = {
      # Rose Pine Dawn colors
      background = palette.background;
      foreground = palette.text;
      cursor = palette.cursor;
      cursor_text_color = palette.background;
      selection_background = palette.highlightMed;
      selection_foreground = palette.text;
      url_color = palette.foam;

      # Normal colors
      inherit (kittyAnsi) color0 color1 color2 color3 color4 color5 color6 color7;

      # Bright colors
      inherit
        (kittyAnsi)
        color8
        color9
        color10
        color11
        color12
        color13
        color14
        color15
        ;

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
      active_tab_background = palette.foam;
      active_tab_foreground = palette.background;
      inactive_tab_background = palette.overlay;
      inactive_tab_foreground = palette.text;

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
