# Omarchy v4 shell environment — ADR-0007 Stage 2, wired in at Stage 4.
#
# Ships the vendored QuickShell shell tree + IPC wrappers alongside
# quickshell. Since the Stage 4 stack swap, the shell is started by the
# compositor's autostart (uwsm-wrapped `omarchy-launch-shell`) and has
# replaced the v3 stack (waybar/walker/…).
{
  config,
  lib,
  pkgs,
  inputs,
  username,
  system,
  ...
}: let
  omarchy = import ../../packages/omarchy {
    inherit pkgs;
    hyprland = inputs.hyprland.packages.${system}.hyprland;
  };
  theme = import ../../packages/omarchy/theme.nix {inherit pkgs omarchy;};
in {
  home.packages = [
    omarchy
    pkgs.quickshell
    pkgs.inotify-tools
  ];

  # The OMARCHY_PATH contract: shell QML, the wrappers, and (Stage 3) the
  # Hyprland Lua layer all read it. home.sessionVariables lands in both the
  # shell profile and the systemd user environment (environment.d).
  home.sessionVariables.OMARCHY_PATH = "${omarchy}";

  # Stage 5: materialize the staged theme the shell reads at startup (Color.qml
  # reads exactly these two files, watchChanges: false). Both are rendered at
  # build time by the vendored upstream template engine — rebuild to retheme,
  # then restart the shell (omarchy-restart-shell) or relogin. HM deliberately
  # owns this generated state because multi-theme switching is out of scope
  # (ADR-0007 Stage 5): if omarchy-theme-set is ever run manually, HM restores
  # these files on the next switch (pre-existing copies get the hm-backup
  # suffix).
  home.file.".local/state/omarchy/current/theme/colors.toml".source = "${theme}/colors.toml";
  home.file.".local/state/omarchy/current/theme/shell.toml".source = "${theme}/shell.toml";
}
