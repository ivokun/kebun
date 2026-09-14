# Den diagrams — mermaid sections for README (r17x/universe den-2 style).
#
# Auto-discovered from the den aspect tree (capture API + den-diagram).
# No manual entries and no SVG builds — pure mermaid source, rendered by
# GitHub's native mermaid support.
#
# README sections (inside BEGIN/END:AUTO-GENERATED markers):
#   1. Overview         — namespace graph (all aspects + includes)
#   2. Hosts            — per-host resolved aspect trees (collapsible)
#   3. Home Manager     — per-user trees (collapsible)
#   4. Dependencies     — full namespace graph
#   plus a `graph` text package for LLM consumption.
{
  self,
  config,
  lib,
  inputs,
  ...
}: let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  den = config.den;
  diagramLib = import "${inputs.den-diagram}/nix" {inherit lib;};

  # Rose Pine Dawn palette (same source of truth as lib/palette.nix).
  edgePalette = {
    base00 = "#faf4ed";
    base01 = "#fffaf3";
    base02 = "#f2e9e1";
    base03 = "#9893a5";
    base04 = "#797593";
    base05 = "#575279";
    base06 = "#575279";
    base07 = "#1f1d2e";
    base08 = "#b4637a";
    base09 = "#ea9d34";
    base0A = "#d7827e";
    base0B = "#286983";
    base0C = "#56949f";
    base0D = "#907aa9";
    base0E = "#d685af";
    base0F = "#a9333e";
  };

  theme = diagramLib.themeFromPalette edgePalette;
  renderers = diagramLib.renderers {inherit theme;};

  # --- Auto-discovery ---
  fleetCapture = den.lib.capture.captureFleet {};
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  namespaceGraph = diagramLib.graph.ofNamespace {aspects = den.aspects or {};};
  overviewMermaid = renderers.toMermaid namespaceGraph;

  hostSections =
    map (
      host: let
        graph = diagramLib.projectScope {
          inherit fleetCapture;
          kind = "host";
          name = host.name;
        };
      in {
        name = host.name;
        mermaid = renderers.toMermaid graph;
      }
    )
    allHosts;

  userEntries =
    lib.concatMap (
      host:
        lib.mapAttrsToList (
          userName: _: {
            inherit host userName;
          }
        ) (host.users or {})
    )
    allHosts;

  userSections =
    map (
      u: let
        graph = diagramLib.projectScope {
          inherit fleetCapture;
          kind = "user";
          name = u.userName;
        };
      in {
        name = "${u.userName}@${u.host.name}";
        mermaid = renderers.toMermaid graph;
      }
    )
    userEntries;

  # --- LLM-friendly text summary ---
  textLib = diagramLib.text;
  fleetSummaryText = textLib.fleetSummary fleetCapture;
  hostSummaryTexts =
    map (
      host: let
        graph = diagramLib.projectScope {
          inherit fleetCapture;
          kind = "host";
          name = host.name;
        };
      in
        textLib.hostSummary {
          inherit graph;
          inherit fleetCapture;
        }
    )
    allHosts;
  fullSummary = lib.concatStringsSep "\n\n---\n\n" ([fleetSummaryText] ++ hostSummaryTexts);

  # --- README section composition ---
  mermaidBlock = src: "```mermaid\n${src}\n```";

  collapsible = title: content: ''
    <details>
    <summary>${title}</summary>

    ${content}

    </details>'';

  sectionDrv = pkgs.writeText "readme-section.md" (lib.concatStringsSep "\n\n" (
    [
      "### Overview"
      (mermaidBlock overviewMermaid)
      "### Hosts"
    ]
    ++ map (h: collapsible h.name (mermaidBlock h.mermaid)) hostSections
    ++ ["### Home Manager"]
    ++ map (u: collapsible u.name (mermaidBlock u.mermaid)) userSections
    ++ [
      "### Dependencies"
      (mermaidBlock overviewMermaid)
    ]
  ));

  readmeMarkerTop = "<!-- BEGIN:AUTO-GENERATED -->";
  readmeMarkerEnd = "<!-- END:AUTO-GENERATED -->";
in {
  flake.packages.x86_64-linux = {
    diagrams-mermaid = pkgs.writeText "architecture.mmd" overviewMermaid;
    graph = pkgs.writeShellScriptBin "graph" ''
      cat ${pkgs.writeText "graph.md" fullSummary}
    '';
    update-readme = pkgs.writeShellScriptBin "update-readme" ''
      set -euo pipefail
      ROOT="$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
      README="$ROOT/README.md"

      ${pkgs.coreutils}/bin/touch "$README"
      if ! ${pkgs.gnugrep}/bin/grep -q "^${readmeMarkerTop}$" "$README"; then
        printf '%s\n%s\n' "${readmeMarkerTop}" "${readmeMarkerEnd}" >> "$README"
      fi

      BEFORE=$(${pkgs.gnused}/bin/sed "/^${readmeMarkerTop}$/q" "$README")
      AFTER=$(${pkgs.gnused}/bin/sed -n "/^${readmeMarkerEnd}$/,\$p" "$README")

      {
        printf '%s\n\n' "$BEFORE"
        cat ${sectionDrv}
        printf '\n\n%s\n' "$AFTER"
      } > "$README.tmp"

      ${pkgs.coreutils}/bin/mv "$README.tmp" "$README"
    '';
  };
}
