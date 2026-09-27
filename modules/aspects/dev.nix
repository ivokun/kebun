{
  config,
  lib,
  pkgs,
  ...
}: {
  # ─── Rootless Docker (shared workstation policy) ───
  # Preserves the lazydocker workflow without granting the desktop user
  # root-equivalent access to the system daemon socket.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  environment.systemPackages = with pkgs; [
    gcc
    gnumake
    cmake
    pkg-config
    tree-sitter
    figlet

    go
    nodejs
    python3

    docker-compose

    nixfmt
    alejandra
    nixd

    postgresql
    sqlite

    # OpenCode is installed by home/features/opencode.nix through the managed
    # wrapper. Do not expose the raw package through the system profile: it
    # would bypass update blocking and ambient GitHub-token cleanup.
    awscli2
    bun
    pnpm_10
    uv
  ];
}
