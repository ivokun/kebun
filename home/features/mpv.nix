{ config, pkgs, ... }: {
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
      background-color = "#faf4ed";
      screenshot-template = "%F_%P";
      screenshot-directory = "~~desktop/";
    };

    scripts = with pkgs.mpvScripts; [
      uosc        # Modern customizable UI
      thumbfast   # Thumbnail preview on seek bar
    ];

    # uosc theme configuration (Rose Pine Dawn inspired)
    scriptOpts = {
      uosc = {
        font = "CaskaydiaMono Nerd Font";
        font_size = 16;
        background = "#faf4ed";
        background_text = "#797593";
        foreground = "#575279";
        foreground_text = "#faf4ed";
        accent = "#56949f";
        curve = 0;
        bar_color = "#56949f";
        timeline_size = 30;
        controls = "play_pause,chapter_prev,chapter_next,volume,loop,audio,sub,video,playlist,fullscreen";
      };
    };
  };
}
