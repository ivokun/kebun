# OpenCode V2 is not yet packaged by the pinned nixpkgs revision (nixpkgs'
# opencode/opencode-desktop are still the V1 1.x series).
# Keep this shared between NixOS and Home Manager: nested Home Manager evaluates
# its own package set, so a host-only overlay would silently leave the managed
# user wrapper on nixpkgs' V1 package.
final: _prev: let
  # v2.0.29's lockfile/patches are built for Bun 1.3.x; see the file header.
  bun-1-3 = final.callPackage ../packages/opencode/bun-1.3.13.nix {};
in {
  opencode = final.callPackage ../packages/opencode/opencode-v2.nix {
    bun = bun-1-3;
  };
  opencode-desktop = final.callPackage ../packages/opencode/opencode-desktop.nix {
    bun = bun-1-3;
  };
}
