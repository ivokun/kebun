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

  # IME toggle trigger: Alt+Space instead of the fcitx5 default Ctrl+Space.
  # Declaring TriggerKeys replaces the defaults outright. Plain ALT+SPACE is
  # unbound in both kebun's and upstream's Hyprland bindings, and on Wayland
  # the trigger is handled by fcitx5 via input-method-v2 before apps see it.
  xdg.configFile."fcitx5/config".text = ''
    [Hotkey]
    TriggerKeys=
    0=Alt+space
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
