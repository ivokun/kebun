# OpenCode Desktop — the Electron GUI, built from the same vendored upstream
# source tree as the CLI (packages/opencode/opencode-v2.nix). Ported from
# upstream's nix/desktop.nix (tag v2.0.18) with kebun adaptations:
#
# - The bundled sidecar CLI is the vendored opencode derivation, so the app
#   runs the exact version the managed config targets. A package.json stub is
#   staged beside it because the prebuild reads its version to stamp
#   resources/opencode-cli.version (upstream's desktop.nix omits the stub and
#   fails).
# - The desktop auto-updater is disabled at source, like nixpkgs' V1
#   packaging: electron-updater would download and exec an upstream-packaged
#   app that is not patched for NixOS. Updates happen through this repository.
# - electron-builder unpacks native .node modules (the @lydell/node-pty
#   binding is externalized by electron-vite and dlopened at runtime).
# - The bundled CLI copy is the wrapper produced by opencode-v2.nix, so the
#   sidecar keeps its ripgrep PATH and wayland library setup.
{
  lib,
  stdenv,
  stdenvNoCC,
  bun,
  nodejs,
  callPackage,
  makeWrapper,
  writableTmpDirAsHomeHook,
  autoPatchelfHook,
  copyDesktopItems,
  makeDesktopItem,
  opencode,
}: let
  electron = callPackage ./electron.nix {};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "opencode-desktop";
    inherit (opencode) version src node_modules;

    nativeBuildInputs =
      [
        bun
        nodejs # for patchShebangs node_modules
        makeWrapper
        writableTmpDirAsHomeHook
      ]
      ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
        autoPatchelfHook
        copyDesktopItems
      ];

    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
      (lib.getLib stdenv.cc.cc)
    ];
    # The musl prebuilts ship libc.musl-*.so.1 SONAMEs that autoPatchelfHook
    # cannot resolve on glibc systems; they are not loaded at runtime there.
    autoPatchelfIgnoreMissingDeps = ["libc.musl-x86_64.so.1"];

    desktopItems = lib.optional stdenvNoCC.hostPlatform.isLinux (makeDesktopItem {
      name = "ai.opencode.desktop";
      desktopName = "OpenCode";
      exec = "opencode-desktop %U";
      icon = "ai.opencode.desktop";
      # Electron derives the X11 WM_CLASS from app.name — "OpenCode" on prod.
      startupWMClass = "OpenCode";
      categories = ["Development"];
      mimeTypes = ["x-scheme-handler/opencode"];
    });

    env =
      opencode.env
      // {
        ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
      };

    postPatch =
      # NOTE: Relax Bun version check to be a warning instead of an error
      ''
        substituteInPlace packages/script/src/index.ts \
          --replace-fail 'throw new Error(`This script requires bun@''${expectedBunVersionRange}' \
                         'console.warn(`Warning: This script requires bun@''${expectedBunVersionRange}'

        # The desktop auto-updater would download and run an upstream binary
        # that is not patched for NixOS. Disable it at source.
        substituteInPlace packages/desktop/src/main/constants.ts \
          --replace-fail 'app.isPackaged && CHANNEL !== "dev"' 'false'
      ''
      # https://github.com/electron/electron/issues/31121 — app.asar is passed
      # as a flag to a non-standard location, so process.resourcesPath does
      # not point at the app resources.
      + lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        substituteInPlace \
          packages/desktop/src/main/windows/appearance.ts \
          packages/desktop/src/main/service/desktop-cli.ts \
          --replace-fail "process.resourcesPath" "'$out/opt/opencode-desktop/resources'"
      '';

    preBuild = ''
      # Phases share one shell: capture the package dir before buildPhase's cd
      # so installPhase can return to it regardless of where build left off.
      desktopDir="$PWD/packages/desktop"

      cp -r "${electron.dist}" $HOME/.electron-dist
      chmod -R u+w $HOME/.electron-dist

      cp -R ${finalAttrs.node_modules}/. .
      patchShebangs node_modules
      patchShebangs packages/*/node_modules
    '';

    buildPhase = ''
      runHook preBuild

      cd packages/desktop

      # Stage the vendored CLI where prebuild's copyBuiltCliToResources
      # expects an npm-style CLI package: <dir>/bin/opencode plus a
      # package.json whose version becomes resources/opencode-cli.version.
      export OPENCODE_CLI_DIST="$TMPDIR/desktop-cli"
      cli_package="$OPENCODE_CLI_DIST/cli-linux-x64-baseline"
      mkdir -p "$cli_package/bin"
      cp ${lib.getExe opencode} "$cli_package/bin/opencode"
      echo '{"name":"@opencode/cli-linux-x64-baseline","version":"'"${finalAttrs.version}"'"}' > "$cli_package/package.json"

      bun run build
      npx electron-builder --dir \
        --config electron-builder.config.ts \
        --config.electronDist="$HOME/.electron-dist" \
        --config.electronVersion="${electron.version}" \
        --config.asarUnpack='**/*.node'

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cd "$desktopDir"
      mkdir -p $out/opt/opencode-desktop
      [ -d dist/linux-unpacked ] || {
        echo "no electron-builder output dir found: dist/linux-unpacked" >&2
        exit 1
      }
      cp -r dist/linux-unpacked/resources $out/opt/opencode-desktop/

      for size in 32 64 128; do
        install -Dm644 resources/icons/''${size}x''${size}.png \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/ai.opencode.desktop.png"
      done
      install -Dm644 resources/icons/128x128@2x.png \
        "$out/share/icons/hicolor/256x256/apps/ai.opencode.desktop.png"
      install -Dm644 resources/icons/icon.png \
        "$out/share/icons/hicolor/512x512/apps/ai.opencode.desktop.png"
      install -Dm644 resources/ai.opencode.desktop.metainfo.xml \
        "$out/share/metainfo/ai.opencode.desktop.metainfo.xml"

      makeWrapper ${lib.getExe electron} $out/bin/opencode-desktop \
        --inherit-argv0 \
        --set ELECTRON_FORCE_IS_PACKAGED 1 \
        --add-flags $out/opt/opencode-desktop/resources/app.asar \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3}}"

      runHook postInstall
    '';

    meta = {
      description = "OpenCode Desktop App";
      homepage = "https://opencode.ai";
      license = lib.licenses.mit;
      mainProgram = "opencode-desktop";
      platforms = ["x86_64-linux"];
    };
  })
