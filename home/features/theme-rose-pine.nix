{
  config,
  lib,
  pkgs,
  ...
}: {
  # Palette lives in lib/palette.nix (ADR-0007 Stage 5 single-sourcing).
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
