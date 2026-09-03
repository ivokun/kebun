# Rose Pine Dawn staged theme (ADR-0007 Stage 5).
#
# Renders the staged theme dir at BUILD TIME with the vendored upstream
# template engine (omarchy-theme-set-templates): no runtime staging, no
# omarchy-theme-set. The shell reads exactly two files from
# $HOME/.local/state/omarchy/current/theme/ at startup (Color.qml,
# watchChanges: false), so only those two are installed.
{
  pkgs,
  # The omarchy-shell-env package (pass from the consumer): provides
  # default/themed/*.tpl — the tree the renderer consumes.
  omarchy,
  palette ? import ../../lib/palette.nix,
}: let
  colorsFile = pkgs.writeText "colors.toml" palette.colorsToml;
in
  pkgs.runCommand "omarchy-theme-rose-pine-dawn" {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gawk
      gnugrep
      gnused
    ];
  } ''
    # The upstream scripts carry #!/bin/bash shebangs (absent in the build
    # sandbox) and are not in the vendored wrap list, so stage patched
    # copies rather than reimplementing the renderer.
    bin=$(mktemp -d)
    for script in omarchy-theme-set-templates omarchy-theme-color; do
      cp ${omarchy}/bin/$script $bin/
    done
    patchShebangs $bin
    export PATH=$bin:$PATH

    # Renderer contract: templates from $OMARCHY_PATH/default/themed, input
    # at $HOME/.local/state/omarchy/current/next-theme/colors.toml, output
    # rendered into that same directory.
    export OMARCHY_PATH=${omarchy}
    export HOME=$(mktemp -d)
    next=$HOME/.local/state/omarchy/current/next-theme
    mkdir -p $next
    cp ${colorsFile} $next/colors.toml

    omarchy-theme-set-templates

    # The shell reads exactly these two files; the other 15 rendered
    # templates are dead weight for kebun.
    mkdir -p $out
    cp ${colorsFile} $out/colors.toml
    cp $next/shell.toml $out/shell.toml

    # No unresolved {{ placeholder }} may survive.
    if grep -q '{{' $out/shell.toml; then
      echo "omarchy-theme-rose-pine-dawn: unresolved placeholders in shell.toml" >&2
      grep -n '{{' $out/shell.toml >&2
      exit 1
    fi
  ''
