# OpenCode V2 is not yet packaged by the pinned nixpkgs revision.
# Keep this shared between NixOS and Home Manager: nested Home Manager evaluates
# its own package set, so a host-only overlay would silently leave the managed
# user wrapper on nixpkgs' V1 package.
final: _prev: {
  opencode = final.callPackage ../packages/opencode/opencode-v2.nix {};
}
