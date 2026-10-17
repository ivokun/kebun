# Claude Code — nixpkgs' derivation, re-pointed at a newer upstream release.
#
# The pinned nixpkgs revision trails Anthropic's release channel by weeks, and
# the CLI's auto-updater is disabled in the store (DISABLE_AUTOUPDATER=1), so
# the version is whatever this repo says it is. nixpkgs' package already takes
# the release `manifest` as an argument, so the whole override is swapping in a
# manifest fetched from the same channel its own update.sh uses — no fork of
# the build logic, and nixpkgs keeps owning the wrapper/patchelf side.
#
# Updates: re-fetch the manifest for the newest release —
#   curl -fsSL https://downloads.claude.ai/claude-code-releases/latest
#   curl -fsSL https://downloads.claude.ai/claude-code-releases/<ver>/manifest.json \
#     --output packages/claude-code/manifest.json
# ("latest" is the newest build; "stable" is the slower channel — nixpkgs
# tracks "latest".) The checksums in the manifest *are* the fixed-output
# hashes, so there is nothing else to prefetch.
#
# Caveat on nixpkgs bumps: this manifest must match the shape the pinned
# derivation expects — the plain `claude` binary. Newer nixpkgs revisions fetch
# the zstd-compressed artifact and read `manifest.zst.json` instead; after a
# flake update, re-fetch accordingly (`.../manifest.zst.json`) or drop this
# override if nixpkgs has caught up. A mismatch fails the build, not silently
# at runtime.
#
# Drop this directory entirely once the pinned nixpkgs ships a version that is
# new enough.
{
  lib,
  claude-code,
}:
claude-code.override {
  manifest = lib.importJSON ./manifest.json;
}
