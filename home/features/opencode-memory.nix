# One database owner per user, shared by every OpenCode stdio adapter.
# It follows the user manager, not the graphical session or remote network.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  memory = pkgs.callPackage ../../packages/opencode/memory.nix {};
  host = osConfig.kebun.host;
  sync = host.memorySync;
  stateDir = "${config.home.homeDirectory}/.local/state/kebun-memory";
  socket = "%t/kebun-memory/memory.sock";
  # ExecStart is parsed by systemd, not a shell. Only the socket's %t is
  # intentional; literal '%'/'$' in configured paths/URLs must not expand.
  unitLiteral = lib.replaceStrings ["%" "$"] ["%%" "$$"];
  daemonArguments =
    [
      "${memory}/bin/kebun-memory"
      "daemon"
      "--state-dir"
      (unitLiteral stateDir)
      "--socket"
      socket
      "--account-id"
      host.memoryAccountId
      "--actor-id"
      host.memoryActorId
    ]
    ++ lib.optionals (sync.enable && sync.url != null && sync.tokenFile != null) [
      "--sync-url"
      (unitLiteral sync.url)
      "--token-file"
      (unitLiteral sync.tokenFile)
    ];
  # Type=exec alone only confirms that Node started, not that PGlite and the
  # socket are usable. Check local status only: remote health is never a
  # prerequisite. Do not print memory contents or synchronization credentials.
  ready = pkgs.writeShellScript "kebun-memory-ready" ''
    set -eu
    for attempt in {1..200}; do
      if ${memory}/bin/kebun-memory status \
        --socket "$1" >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    echo "kebun-memory: local readiness check timed out" >&2
    exit 1
  '';
in {
  home.packages = [memory];

  systemd.user.services.kebun-memory = {
    Unit.Description = "Kebun local-first memory daemon";
    Install.WantedBy = ["default.target"];
    Service = {
      Type = "exec";
      ExecStart = lib.escapeShellArgs daemonArguments;
      ExecStartPost = "${ready} ${socket}";
      Restart = "on-failure";
      RestartSec = 3;
      # A duplicate owner is an operator error, not a stale-lock takeover.
      RestartPreventExitStatus = [75];
      TimeoutStartSec = 60;
      TimeoutStopSec = 30;
      UMask = "0077";
      StateDirectory = "kebun-memory";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "kebun-memory";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "no";
      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = ["AF_UNIX"] ++ lib.optionals sync.enable ["AF_INET" "AF_INET6"];
      Environment = ["NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];
      UnsetEnvironment = [
        "GITHUB_TOKEN"
        "GH_TOKEN"
        "GITHUB_PERSONAL_ACCESS_TOKEN"
        "GITHUB_ENTERPRISE_TOKEN"
        "GH_ENTERPRISE_TOKEN"
      ];
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "kebun-memory";
    };
  };
}
