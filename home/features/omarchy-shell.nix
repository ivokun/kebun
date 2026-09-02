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
}
