# This artifact is deliberately independent of nixosConfigurations and the
# desktop closure. Pasal can pin an immutable Kebun revision and consume
# packages.<system>.kebun-memory-server (bin/kebun-memory sync-server).
{
  inputs,
  lib,
  ...
}: {
  flake.packages = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    memory = pkgs.callPackage ../packages/opencode/memory.nix {};
  in {
    kebun-memory = memory;
    kebun-memory-server = memory;
  });

  flake.checks = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    memory = pkgs.callPackage ../packages/opencode/memory.nix {};
  in {
    kebun-memory = pkgs.callPackage ../packages/opencode/memory-check.nix {inherit memory;};
  });
}
