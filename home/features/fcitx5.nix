{
  config,
  lib,
  pkgs,
  ...
}: {
  # Fcitx5 is enabled at the NixOS level in hosts/common/desktop.nix
  # (i18n.inputMethod is a NixOS module option, not a home-manager option)
  # This module handles user-level configuration only.

  home.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };

  # Fcitx5 profile for Mozc
  xdg.configFile."fcitx5/conf/xcb.conf".text = ''
    Allow Overriding System XKB Settings=False
    Always set layout to the default layout only=False
  '';

  xdg.configFile."fcitx5/profile".text = ''
    [Groups/0]
    Name=Default
    Default Layout=us
    DefaultIM=mozc

    [Groups/0/Items/0]
    Name=keyboard-us
    Layout=

    [Groups/0/Items/1]
    Name=mozc
    Layout=
  '';
}
