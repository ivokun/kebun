# Aspect resolution diagrams (den-diagram).
#
# Renders views for the sakura host and the ivokun user into
# subdirectories under diagrams/:
#
#   diagrams/
#     hosts/sakura/          — per-host views + DAG
#     hosts/sakura/users/ivokun/ — per-user views
#     fleet/                 — fleet-wide views
#
# Requires the den-diagram input (see flake.nix).
{
  den,
  lib,
  self,
  inputs,
  ...
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  diagram = inputs.den-diagram.lib;

  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);

  # Base16 scheme name used for all rendered views.
  themeScheme = "rose-pine-dawn";

  # Patched mermaid-cli: swap bundled mermaid@11.12.0 for 11.14.0
  # so recent diagram types render. Drop once nixpkgs bundles ≥11.14.
  mermaidCliPatched = pkgs.mermaid-cli.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      mermaid_dir="$out/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/mermaid"
      if [ ! -d "$mermaid_dir" ]; then
        echo "mermaidCliPatched: expected $mermaid_dir to exist." >&2
        exit 1
      fi
      rm -rf "$mermaid_dir"
      mkdir -p "$mermaid_dir"
      ${pkgs.gnutar}/bin/tar -xzf ${
        pkgs.fetchurl {
          url = "https://registry.npmjs.org/mermaid/-/mermaid-11.14.0.tgz";
          hash = "sha256-Y7oGZJ4X4Q/uAuVMfC7az+JQtLvds8JJfwDToypC5cc=";
        }
      } -C "$mermaid_dir" --strip-components=1
    '';
  });

  rc = diagram.renderContext {
    inherit pkgs;
    theme = diagram.themeFromBase16 {
      inherit pkgs;
      scheme = themeScheme;
    };
    mermaidCli = mermaidCliPatched;
    mermaidConfig = {
      layout = "elk";
      elk = {
        mergeEdges = true;
        nodePlacementStrategy = "BRANDES_KOEPF";
      };
      flowchart = {
        wrappingWidth = 600;
      };
    };
  };

  fleetCapture = den.lib.capture.captureFleet { };

  fleetData = diagram.fleet.of {
    hosts = den.hosts;
    flakeName = "kebun";
  };

  # View definitions. Class views are appended dynamically per entity.
  hostViewDefs =
    classes:
    rc.views.host ++ rc.views.classViews classes;
  userViewDefs =
    classes:
    rc.views.user ++ rc.views.classViews classes;
  fleetViewDefs = rc.views.fleet;

  inherit (diagram.export)
    entityEntries
    filterByRender
    mkGallery
    mkWriteScript
    entriesToPackages
    entriesToFiles
    ;

  graphClasses = entity: lib.unique (lib.concatMap (n: n.classes or [ ]) entity.nodes);

  mkHostEntity =
    host:
    diagram.projectScope {
      inherit fleetCapture;
      kind = "host";
      name = host.name;
    };

  mkUserEntity =
    u:
    diagram.projectScope {
      inherit fleetCapture;
      kind = "user";
      name = u.userName;
    };

  allUsers = lib.concatMap (
    host:
    lib.mapAttrsToList (userName: user: {
      inherit host user userName;
      name = "${host.name}-${userName}";
    }) (host.users or { })
  ) allHosts;

  filteredUsers = filterByRender {
    all = allUsers;
    renderList = true;
    getKey = u: u.userName;
  };

  userEntries = lib.concatMap (
    u:
    let
      entity = mkUserEntity u;
    in
    entityEntries { inherit pkgs rc; } {
      inherit entity;
      name = u.userName;
      dir = "hosts/${u.host.name}/users/${u.userName}";
      viewDefs = userViewDefs (graphClasses entity);
    }
  ) filteredUsers;

  hostEntries = lib.concatMap (
    host:
    let
      entity = mkHostEntity host;
    in
    entityEntries { inherit pkgs rc; } {
      inherit entity;
      name = host.name;
      dir = "hosts/${host.name}";
      viewDefs = hostViewDefs (graphClasses entity);
    }
  ) allHosts;

  # --- Fleet views ---

  mkFleetView =
    name: title: renderFn:
    let
      source = renderFn fleetCapture;
      md = pkgs.writeText "${name}.md" "# ${title}\n\n![${title}](./${name}.mmd.svg)\n\n```mermaid\n${source}\n```\n";
      svg = rc.mmdSourceToSvg name source;
    in
    {
      inherit md svg;
    };

  hostGraphs = lib.listToAttrs (
    map (
      host: {
        name = host.name;
        value = mkHostEntity host;
      }
    ) allHosts
  );

  fleetDagSource = rc.render.toFleetDagMermaid {
    inherit fleetCapture hostGraphs;
  };

  fleetViews = {
    pipe-flow = mkFleetView "pipe-flow" "Pipe Flow" rc.render.toPipeFlowMermaid;
    scope-topology = mkFleetView "scope-topology" "Scope Topology" rc.render.toScopeTopologyMermaid;
    aspect-matrix = mkFleetView "aspect-matrix" "Aspect Coverage" rc.render.toAspectMatrixMermaid;
    policy-map = mkFleetView "policy-map" "Policy Resolution Map" rc.render.toPolicyResolutionMapMermaid;
    pipe-seq = mkFleetView "pipe-seq" "Pipe Sequence" rc.render.toPipeSequenceMermaid;
  };

  fleetDagView = {
    md = pkgs.writeText "fleet-dag.md" "# Fleet DAG\n\n![Fleet DAG](./fleet-dag.mmd.svg)\n\n```mermaid\n${fleetDagSource}\n```\n";
    svg = rc.mmdSourceToSvg "fleet-dag" fleetDagSource;
  };

  namespaceGraph = diagram.graph.ofNamespace {
    aspects = den.aspects or { };
  };
  namespaceSource = rc.renderDense.toMermaid namespaceGraph;
  namespaceView = {
    md = pkgs.writeText "namespace.md" "# Namespace\n\n![Namespace](./namespace.mmd.svg)\n\n```mermaid\n${namespaceSource}\n```\n";
    svg = rc.mmdSourceToSvg "namespace" namespaceSource;
  };

  fleetEntriesList =
    lib.concatLists (
      lib.mapAttrsToList (
        viewName: view: [
          {
            name = "fleet";
            view = viewName;
            dir = "fleet";
            ext = "md";
            tool = null;
            drv = view.md;
          }
          {
            name = "fleet";
            view = viewName;
            dir = "fleet";
            ext = "svg";
            tool = "mmd";
            drv = view.svg;
          }
        ]
      ) fleetViews
    )
    ++ [
      {
        name = "fleet";
        view = "fleet-dag";
        dir = "fleet";
        ext = "md";
        tool = null;
        drv = fleetDagView.md;
      }
      {
        name = "fleet";
        view = "fleet-dag";
        dir = "fleet";
        ext = "svg";
        tool = "mmd";
        drv = fleetDagView.svg;
      }
      {
        name = "fleet";
        view = "namespace";
        dir = "fleet";
        ext = "md";
        tool = null;
        drv = namespaceView.md;
      }
      {
        name = "fleet";
        view = "namespace";
        dir = "fleet";
        ext = "svg";
        tool = "mmd";
        drv = namespaceView.svg;
      }
    ];

  everyEntry = hostEntries ++ userEntries ++ fleetEntriesList;
  allPackages = entriesToPackages everyEntry;
  allFiles = entriesToFiles everyEntry;

  # --- Galleries ---

  hostGalleries = map (
    host:
    let
      dir = "hosts/${host.name}";
    in
    {
      path = "diagrams/hosts/${host.name}.md";
      drv = mkGallery pkgs {
        name = host.name;
        inherit dir;
        title = "Gallery: ${host.name}";
        entries = everyEntry;
      };
    }
  ) allHosts;

  userGalleries = map (
    u:
    let
      dir = "hosts/${u.host.name}/users/${u.userName}";
    in
    {
      path = "diagrams/hosts/${u.host.name}/users/${u.userName}.md";
      drv = mkGallery pkgs {
        name = u.userName;
        inherit dir;
        title = "Gallery: ${u.userName} @ ${u.host.name}";
        entries = everyEntry;
      };
    }
  ) filteredUsers;

  fleetGallery = {
    path = "diagrams/fleet.md";
    drv = mkGallery pkgs {
      name = "fleet";
      dir = "fleet";
      title = "Fleet Gallery";
      entries = everyEntry;
    };
  };

  galleries = hostGalleries ++ userGalleries ++ [ fleetGallery ];
in
{
  flake.packages.x86_64-linux =
    allPackages
    // {
      write-diagrams = mkWriteScript pkgs {
        entries = everyEntry;
        inherit galleries;
        destExpr = ''"$(${pkgs.git}/bin/git rev-parse --show-toplevel)"'';
      };
    };
}



