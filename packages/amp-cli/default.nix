# Amp CLI — nixpkgs' derivation, re-pointed at the current upstream release.
#
# Same trick as packages/claude-code: the pinned nixpkgs revision trails
# Amp's release channel (it ships 0.0.1784391370-g49c6a1), and the
# CLI's updater is disabled in the store wrapper (AMP_SKIP_UPDATE_CHECK=1 —
# per upstream docs this turns off ALL update checks, including the
# runner's hourly self-update), so the version is whatever this repo pins.
# amp-cli takes no external manifest, so the whole override is swapping in
# the newer artifact and its hash — nixpkgs keeps owning the build (gunzip,
# autoPatchelf, wrapper, version check).
#
# x86_64-linux only: both kebun hosts are x86_64, and "linux-x64-baseline"
# is the build nixpkgs itself uses (no AVX2 requirement). nixpkgs'
# updateScript is dropped — it targets nixpkgs' package rather than this
# override. Update this file's version and hash together instead.
#
# Updates: check https://static.ampcode.com/cli/cli-version.txt, then swap
# the version and hash below. The `hash` is the fixed-output hash of the
# .gz artifact as fetched; the published
# https://static.ampcode.com/cli/<ver>/linux-x64-baseline-amp.sha256 is the
# hash of the *decompressed* binary — don't use it for fetchurl.
{
  amp-cli,
  fetchurl,
}:
amp-cli.overrideAttrs (finalAttrs: previousAttrs: {
  version = "0.0.1792368068-g91990d";

  src = fetchurl {
    url = "https://static.ampcode.com/cli/${finalAttrs.version}/amp-linux-x64-baseline.gz";
    hash = "sha256-if3hAhmwHZo8zVq3m9XCRkf8q5hCtSTsPZ6GUdddOaw=";
  };

  # Keep passthru.sources consistent with the pinned src (the original
  # derivation reads src = passthru.sources.${system}); only the platform
  # kebun actually runs is pinned. This wholesale-replaces the original
  # passthru, taking the now-misleading updateScript with it.
  passthru = {
    sources.x86_64-linux = finalAttrs.src;
  };

  meta =
    previousAttrs.meta
    // {
      platforms = ["x86_64-linux"];
    };
})
