{
  config,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;
in {
  programs.mpv = {
    enable = true;

    config = {
      profile = "gpu-hq";
      force-window = "immediate";
      hwdec = "auto-safe";
      keep-open = "yes";
      save-position-on-quit = "yes";
      force-seekable = "yes";
      osc = "no";
      border = "no";
      background-color = palette.background;
      screenshot-template = "%F_%P";
      screenshot-directory = "~~desktop/";
    };

    scripts = with pkgs.mpvScripts; [
      uosc # Modern customizable UI
      thumbfast # Thumbnail preview on seek bar
    ];

    # uosc theme configuration (Rose Pine Dawn inspired)
    scriptOpts = {
      uosc = {
        font = "CaskaydiaMono Nerd Font";
        font_size = 16;
        background = palette.background;
        background_text = palette.subtle;
        foreground = palette.text;
        foreground_text = palette.background;
        accent = palette.foam;
        curve = 0;
        bar_color = palette.foam;
        timeline_size = 30;
        controls = "play_pause,chapter_prev,chapter_next,volume,loop,audio,sub,video,playlist,fullscreen";
      };
    };
  };
}
