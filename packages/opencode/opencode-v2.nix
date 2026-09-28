{
  bun,
  fetchFromGitHub,
  installShellFiles,
  lib,
  makeBinaryWrapper,
  models-dev,
  nodejs,
  ripgrep,
  stdenv,
  stdenvNoCC,
  wayland,
  writableTmpDirAsHomeHook,
}: let
  version = "2.0.18";
  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = "sha256-QyzzA9SUnnCunYucJPjZAw/EkUN1EKoDcrFalIOYVps=";
  };

  # V2 is not packaged by the pinned nixpkgs revision. Keep upstream's Bun
  # dependency closure as a fixed-output derivation so registry resolution is
  # hash-pinned and happens only during a Nix build.
  nodeModules = stdenvNoCC.mkDerivation {
    pname = "opencode-node-modules";
    inherit version src;

    impureEnvVars =
      lib.fetchers.proxyImpureEnvVars
      ++ [
        "GIT_PROXY_COMMAND"
        "SOCKS_SERVER"
      ];
    nativeBuildInputs = [bun];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --cpu=x64 \
        --os=linux \
        --filter '!./' \
        --filter './packages/cli' \
        --filter './packages/desktop' \
        --filter './packages/app' \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress
      bun --bun ./nix/scripts/canonicalize-node-modules.ts
      bun --bun ./nix/scripts/normalize-bun-binaries.ts

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      find . -type d -name node_modules -exec cp -R --parents {} $out \;

      runHook postInstall
    '';

    dontFixup = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    # Recomputed with the pinned Nix/Bun toolchain. Upstream v2.0.18's
    # published x86_64-linux hash does not reproduce with its own locked flake.
    outputHash = "sha256-9gJjhes2ueYckAgdeGlPwZcaIDdwB3ZnqK/XHHXhWNs=";
  };
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "opencode";
    inherit version src;
    node_modules = nodeModules;

    nativeBuildInputs = [
      bun
      installShellFiles
      makeBinaryWrapper
      models-dev
      nodejs
      writableTmpDirAsHomeHook
    ];

    # The pinned nixpkgs Bun may lag the version requested by upstream while
    # remaining able to build the CLI. Match upstream's Nix packaging and turn
    # that exact version gate into a warning.
    postPatch = ''
      substituteInPlace packages/script/src/index.ts \
        --replace-fail 'throw new Error(`This script requires bun@''${expectedBunVersionRange}' \
                       'console.warn(`Warning: This script requires bun@''${expectedBunVersionRange}'
    '';

    configurePhase = ''
      runHook preConfigure

      cp -R ${finalAttrs.node_modules}/. .
      patchShebangs node_modules
      patchShebangs packages/*/node_modules

      runHook postConfigure
    '';

    env.MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
    env.OPENCODE_DISABLE_MODELS_FETCH = true;
    env.OPENCODE_VERSION = version;
    env.OPENCODE_CHANNEL = "prod";
    env.NODE_OPTIONS = "--max-old-space-size=4096";

    buildPhase = ''
      runHook preBuild

      cd packages/cli
      bun --bun ./script/build.ts --single --skip-install

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 dist/cli-*/bin/opencode $out/bin/opencode

      # Bun's single-file build bundles @parcel/watcher's JavaScript wrapper
      # but not its native binding. Keep the pinned binding from nodeModules
      # beside the executable and use upstream's explicit override rather than
      # silently degrading recursive directory watches at runtime.
      watcherNode=${finalAttrs.node_modules}/packages/cli/node_modules/@parcel/watcher-linux-x64-glibc/watcher.node
      test -f "$watcherNode" || {
        echo "parcel watcher addon missing from node_modules" >&2
        exit 1
      }
      install -Dm644 "$watcherNode" $out/lib/opencode/watcher.node

      wrapProgram $out/bin/opencode \
        --prefix PATH : ${lib.makeBinPath [ripgrep]} \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [wayland stdenv.cc.cc.lib]} \
        --set-default OPENCODE_PARCEL_WATCHER_PATH $out/lib/opencode/watcher.node \
        --set OPENCODE_DISABLE_AUTOUPDATE 1
      ln -s opencode $out/bin/opencode2

      runHook postInstall
    '';

    postInstall = ''
      installShellCompletion --cmd opencode \
        --bash <($out/bin/opencode --completions bash) \
        --zsh <($out/bin/opencode --completions zsh) \
        --fish <($out/bin/opencode --completions fish)
    '';

    passthru = {
      inherit (finalAttrs) env;
    };

    meta = {
      description = "Open source coding agent";
      homepage = "https://opencode.ai";
      license = lib.licenses.mit;
      mainProgram = "opencode";
      platforms = ["x86_64-linux"];
    };
  })
