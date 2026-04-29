{
  config,
  lib,
  pkgs,
  ...
}: let
  rose-pine-dawn = {
    background = "#faf4ed";
    foreground = "#575279";
    cursor = "#cecacd";
    selection-bg = "#dfdad9";
    accent = "#56949f";

    black = "#f2e9e1";
    red = "#b4637a";
    green = "#286983";
    yellow = "#ea9d34";
    blue = "#56949f";
    magenta = "#907aa9";
    cyan = "#d7827e";
    white = "#575279";

    bright-black = "#9893a5";
    bright-red = "#b4637a";
    bright-green = "#286983";
    bright-yellow = "#ea9d34";
    bright-blue = "#56949f";
    bright-magenta = "#907aa9";
    bright-cyan = "#d7827e";
    bright-white = "#575279";
  };
in {
  # ─── Cursor ───
  home.pointerCursor = {
    name = "rose-pine-hyprcursor";
    package = pkgs.rose-pine-hyprcursor;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # ─── dconf settings for GTK ───
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-light";
      gtk-theme = "rose-pine-dawn";
      icon-theme = "Yaru-blue";
      cursor-theme = "rose-pine-hyprcursor";
      cursor-size = 24;
      font-name = "CaskaydiaMono Nerd Font 12";
    };
  };

  # ─── GTK2/3/4 settings ───
  gtk = {
    enable = true;
    theme = {
      name = "rose-pine-dawn";
      package = pkgs.rose-pine-gtk-theme;
    };
    iconTheme = {
      name = "Yaru-blue";
      package = pkgs.yaru-theme;
    };
    cursorTheme = {
      name = "rose-pine-hyprcursor";
      package = pkgs.rose-pine-hyprcursor;
      size = 24;
    };
    font = {
      name = "CaskaydiaMono Nerd Font";
      size = 12;
    };
    gtk3.extraConfig = {
      gtk-xft-antialias = 1;
      gtk-xft-hinting = 1;
      gtk-xft-hintstyle = "hintslight";
      gtk-xft-rgba = "rgb";
      gtk-application-prefer-dark-theme = 0;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 0;
    };
  };

  # ─── qt5ct/qt6ct ───
  home.sessionVariables = {
    QT_STYLE_OVERRIDE = "kvantum";
  };
}
