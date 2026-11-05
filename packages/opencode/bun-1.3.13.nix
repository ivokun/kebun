# OpenCode v2.0.29's fixed-output dependency tree was produced with Bun
# 1.3.13. nixpkgs 26.11 ships Bun 1.4.4, whose patchedDependencies handling
# no longer applies the source tree's photon-node patch ("hunk #10 does not
# apply"), so the node_modules fixed-output build fails. Pin the Bun release
# that matches the source tree for the OpenCode packages only; the system Bun
# stays at the nixpkgs version.
{
  bun,
  fetchurl,
}:
bun.overrideAttrs (_: {
  version = "1.3.13";
  src = fetchurl {
    url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.13/bun-linux-x64.zip";
    hash = "sha256-ecB3H6i5LDOq5B4VoODTB+qZ0OLwAxfHHGxTI3p44lo=";
  };
})
