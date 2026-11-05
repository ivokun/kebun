# Regression check for the screenshot capture pipeline.
#
# Upstream Omarchy rev 8a787b6 replaced its grim/slurp screenshot
# implementation with `omasnap`, but the vendored tree carries no binary.
# Before packages/omarchy gained the omasnap runtime dependency, both the
# PRINT binding's `omarchy-capture-screenshot` and the clipboard-history image
# action exited 127 ("omasnap: not found"). This check exercises the real
# wrapped scripts — no compositor or actual capture is needed, only PATH
# resolution inside the generated wrappers.
{
  inputs,
  lib,
  ...
}: {
  flake.checks = lib.genAttrs ["x86_64-linux"] (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    omarchy = pkgs.callPackage ../packages/omarchy {};
  in {
    omarchy-capture-screenshot =
      pkgs.runCommand "omarchy-capture-screenshot-check" {
        nativeBuildInputs = [omarchy];
      } ''
        export QT_QPA_PLATFORM=offscreen
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.local/state/omarchy"

        # PRINT binding entry point. Under the regression this is exit 127.
        omarchy-capture-screenshot --help > help.txt
        grep -q "omasnap" help.txt

        # Clipboard-history image action: same omasnap dependency, reached
        # through jq. A missing image makes omasnap exit non-zero, but it must
        # have been executed — 127 means the wrapper's PATH lost omasnap/jq.
        printf '[{"type":"image","path":"/nonexistent/omasnap-check.png"}]' \
          > "$HOME/.local/state/omarchy/clipboard-history.json"
        set +e
        omarchy-clipboard-open --history-index 0 > /dev/null 2> clipboard.err
        status=$?
        set -e
        test "$status" -ne 127
        ! grep -qi "not found" clipboard.err

        touch $out
      '';
  });
}
