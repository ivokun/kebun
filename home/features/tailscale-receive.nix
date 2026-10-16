# Taildrop receiver — port of upstream Omarchy v4.0.2's
# default/systemd/user/omarchy-tailscale-receive.service, which upstream's
# omarchy-install-service-tailscale enables alongside the omarchy.tailscale
# bar widget. Kebun installs Tailscale declaratively (modules/aspects/
# networking.nix), so that script never runs; this carries its receive half.
#
# Upstream gates on ConditionPathExists=/usr/bin/tailscale and execs
# /usr/bin/omarchy-tailscale-receive — neither is valid on NixOS, so
# ExecStart is the wrapped store path (tailscale, xdg-open and the
# notification verb resolve from its closure). `tailscale file get` needs the
# operator set by services.tailscale.extraSetFlags; until tailscaled is up it
# fails and the script retries every 10s on its own.
{
  pkgs,
  inputs,
  ...
}: let
  omarchyEnv = import ../../packages/omarchy {
    inherit pkgs;
    hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  };
in {
  systemd.user.services.omarchy-tailscale-receive = {
    Unit = {
      Description = "Save incoming Taildrop files to the downloads directory";
      # Announcements go through the running shell (the notification daemon),
      # so wait for UWSM to import OMARCHY_PATH/WAYLAND_DISPLAY.
      After = ["wayland-session-waitenv.service"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = ["OMARCHY_PATH" "WAYLAND_DISPLAY"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${omarchyEnv}/bin/omarchy-tailscale-receive";
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
