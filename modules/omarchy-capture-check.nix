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
        unset WAYLAND_DISPLAY DISPLAY
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.local/state/omarchy"

        # PRINT binding entry point. Under the regression this is exit 127.
        omarchy-capture-screenshot --help > help.txt
        grep -q "omasnap" help.txt

        # Clipboard-history image action: same omasnap dependency, reached
        # through jq. The fixture must be readable, or the script exits at its
        # own readability guard before exec'ing omasnap and the assertion
        # proves nothing. A file literally named `--version` passes that guard
        # and omasnap treats the dispatched path as its version flag — a
        # deterministic, non-interactive observable that the image branch
        # actually executed omasnap. No Wayland, capture, or overlay involved.
        : > ./--version
        printf '[{"type":"image","path":"--version"}]' \
          > "$HOME/.local/state/omarchy/clipboard-history.json"
        omarchy-clipboard-open --history-index 0 > clipboard.out
        grep -q '^omasnap [0-9]' clipboard.out || {
          echo "clipboard image action did not execute omasnap:" >&2
          cat clipboard.out >&2
          exit 1
        }

        touch $out
      '';
  });
}
