# Pre-suspend locking — port of upstream Omarchy v4.0.2's
# default/systemd/user/omarchy-sleep-lock.service (ADR-0007 Stage 4
# follow-up; upstream's v3 hypridle 900s suspend listener was deliberately
# not carried, but this pre-suspend lock is not idle-suspend and closes the
# "lid closed while unlocked" hole).
#
# The monitor (omarchy-system-sleep-monitor, ExecStart at a store path —
# upstream's /usr/bin/omarchy-system-sleep-monitor is not valid on NixOS)
# holds a delay inhibitor on logind's PrepareForSleep, locks the shell, and
# reports secure before the inhibit window (InhibitDelayMaxSec=15, set in
# modules/aspects/desktop.nix) expires. wayland-session-waitenv.service ships
# with uwsm itself, so the After= resolves once UWSM has imported
# OMARCHY_PATH/WAYLAND_DISPLAY into the user manager.
{
  pkgs,
  inputs,
  ...
}: let
  omarchyEnv = import ../../packages/omarchy {
    inherit pkgs;
    # The pinned compositor build (flake input), not nixpkgs' — same source
    # the desktop aspect and hyprland feature already use.
    hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  };
in {
  systemd.user.services.omarchy-sleep-lock = {
    Unit = {
      Description = "Lock Omarchy before suspend";
      # The monitor calls into the running Omarchy shell. Wait until UWSM has
      # imported OMARCHY_PATH and WAYLAND_DISPLAY, but keep the default target
      # ordering so the monitor starts before graphical-session.target is
      # reached.
      After = ["dbus.socket" "wayland-session-waitenv.service"];
      Requires = ["dbus.socket"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = ["OMARCHY_PATH" "WAYLAND_DISPLAY"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${omarchyEnv}/bin/omarchy-system-sleep-monitor";
      # The inhibitor exits after the lock attempt releases its delay, just
      # before logind suspends. Restarting re-arms it for the next request.
      Restart = "always";
      RestartSec = 2;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
