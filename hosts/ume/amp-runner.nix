# Amp runner — a headless Amp instance serving this machine's dev repos.
#
# `amp --no-tui` is runner mode: it waits for threads started remotely (on
# ampcode.com or another client) and runs them here. --discover-dirs serves
# every git checkout up to two levels beneath the working directory, so
# WorkingDirectory = ~/Documents/dev scopes it to that tree — not the whole
# home; --no-serve-cwd keeps the (non-checkout) devDir itself out of the
# served set.
#
# A system-level service running as ivokun (architecture decision): it
# boots independently of any login session, and system units don't need
# lingering for their User=. The honest caveat is that this is not
# isolation either — the runner runs with ivokun's full privileges, and
# per Amp's docs served directories only "select where a thread starts;
# they do not restrict the files or commands a running thread can access".
# Directory discovery is not a sandbox, and none is attempted here: threads
# can do anything ivokun can, including nix builds. This is the operator's
# own agent runtime on the operator's own machine.
#
# Credentials stay in Amp's own user runtime state; nothing is declared
# here. To (re)authenticate, run `amp login` interactively as ivokun, then
# restart amp-runner so it uses the newly selected account.
#
# Restart=always with StartLimitIntervalSec=0: a failed start (network
# still down at boot, auth hiccup) retries every 30 s forever instead of
# tripping the default start-rate limit and staying dead until reboot.
{
  config,
  lib,
  pkgs,
  ...
}: let
  amp = pkgs.callPackage ../../packages/amp-cli {};

  # From the user declaration, not a hardcoded path or hostname conditional.
  home = config.users.users.ivokun.home;
  devDir = "${home}/Documents/dev";

  # Store packages on the runner's PATH — a superset of the stock service
  # PATH the module system would append (coreutils, findutils, gnugrep,
  # gnused, systemd), which is switched off below in favor of this explicit
  # one. Built bin+sbin the same way the module system builds its own.
  runnerPkgs = with pkgs; [
    bashInteractive
    coreutils
    curl
    findutils
    git
    gnugrep
    gnused
    nix
    openssh
    ripgrep
    systemd
  ];

  # A login shell's PATH, assembled by hand: a boot-time service runs no
  # profile init, so the runtime tool dirs are listed explicitly (each with
  # its /bin suffix once — don't route these through the `path` option,
  # which appends /bin and /sbin to every entry) and the pinned store deps
  # sit beneath them as the guaranteed baseline.
  runnerPath = lib.concatStringsSep ":" [
    "/run/wrappers/bin"
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/ivokun/bin"
    "${home}/.nix-profile/bin"
    (lib.makeBinPath runnerPkgs)
    (lib.makeSearchPathOutput "bin" "sbin" runnerPkgs)
  ];
in {
  # amp on PATH for interactive use (`amp login`, `amp runner dirs add`).
  # List-merges with the host's own environment.systemPackages.
  environment.systemPackages = [amp];

  systemd.services.amp-runner = {
    description = "Amp runner — serves ivokun's git repos under Documents/dev";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];

    # The module system's stock PATH append would clash with the explicit
    # environment.PATH below; it is re-included in runnerPkgs instead.
    enableDefaultPath = false;

    unitConfig = {
      # The working directory and Amp's state live under home.
      RequiresMountsFor = [home];
      # Keep retrying forever; Restart=always below paces it.
      StartLimitIntervalSec = 0;
    };

    serviceConfig = {
      User = "ivokun";
      Group = "users";
      WorkingDirectory = devDir;
      ExecStart = "${lib.getExe amp} --no-tui --runner-id ume --discover-dirs --no-serve-cwd --remote-control-terminal";
      Restart = "always";
      RestartSec = "30s";
    };

    environment = {
      HOME = home;
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      # Standard login defaults — a boot service gets none of this for free.
      XDG_CONFIG_HOME = "${home}/.config";
      XDG_DATA_HOME = "${home}/.local/share";
      XDG_CACHE_HOME = "${home}/.cache";
      XDG_STATE_HOME = "${home}/.local/state";
      # The package wrapper sets this too (it is how the pin holds); repeat
      # it here so the check survives even if the wrapper changes.
      AMP_SKIP_UPDATE_CHECK = "1";
      PATH = runnerPath;
    };
  };
}
