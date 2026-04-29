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

    go
    nodejs
    python3

    docker-compose

    nixfmt-rfc-style
    alejandra
    nixd

    postgresql
    sqlite
  ];
}
