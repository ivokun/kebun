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

    nixfmt-rfc-style
    alejandra
    nixd

    postgresql
    sqlite

    opencode
    awscli2
    bun
    pnpm_9
    uv
  ];
}
