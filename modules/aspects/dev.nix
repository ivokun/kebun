{
  config,
  lib,
  pkgs,
  ...
}: {
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
