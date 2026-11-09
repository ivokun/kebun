# OpenCode V2 is not yet packaged by the pinned nixpkgs revision (nixpkgs'
# opencode/opencode-desktop are still the V1 1.x series).
# Keep this shared between NixOS and Home Manager: nested Home Manager evaluates
# its own package set, so a host-only overlay would silently leave the managed
# user wrapper on nixpkgs' V1 package.
final: _prev: {
  opencode = final.callPackage ../packages/opencode/opencode-v2.nix {};
  # The pinned nixpkgs carries Electron 44, so the desktop build no longer
  # vendors its own Electron derivation.
  opencode-desktop = final.callPackage ../packages/opencode/opencode-desktop.nix {
    electron = final.electron_44-bin;
  };
}
