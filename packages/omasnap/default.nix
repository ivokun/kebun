# Omasnap — the screenshot/annotation overlay Omarchy's capture verbs exec.
#
# Upstream Omarchy rev 8a787b6 delegates screenshots to `omasnap` (see
# omarchy-capture-screenshot and omarchy-clipboard-open's image action), but
# the vendored tree carries no binary and nixpkgs has no `omasnap` attribute.
# Upstream publishes only an x86_64 Arch tarball, so repackage that release
# artifact and supply the Qt/Wayland runtime plus the helper commands it
# expects on PATH.
#
# Artifact verified 2026-11-05: MIT (upstream LICENSE at v1.25.0); the tarball
# itself ships only the bundled font/icon licenses under share/licenses/omasnap,
# so the upstream MIT text is fetched separately and installed there too.
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  qt6,
  kdePackages,
  wayland,
  libdeflate,
  libglvnd,
  gcc-unwrapped,
  wl-clipboard,
  xdg-utils,
  tesseract,
}: let
  version = "1.25.0";

  # The release tarball ships only bundled font/icon notices; the upstream
  # MIT LICENSE is not inside it. Fetch the tagged license text explicitly so
  # the package carries the binary's license alongside those notices.
  licenseSrc = fetchurl {
    url = "https://raw.githubusercontent.com/omacom/omasnap/v${version}/LICENSE";
    hash = "sha256-hG1dzsl+1SISPwz0+CHfswB3RGCj3DGExZWinQK/ShA=";
  };

  # Omasnap's OCR path shells out to tesseract; one language keeps the
  # closure small and matches the capture-text flow kebun actually uses.
  tesseract-eng = tesseract.override {enableLanguages = ["eng"];};
  runtimeDeps = [wl-clipboard xdg-utils tesseract-eng];
in
  stdenvNoCC.mkDerivation {
    pname = "omasnap";
    inherit version;

    src = fetchurl {
      url = "https://github.com/omacom/omasnap/releases/download/v${version}/omasnap-${version}-archlinux-x86_64.tar.gz";
      hash = "sha256-p2t/WAkmh5k65z58d7lYGuCXwNbWX2QgxItcnxj3Dq8=";
    };

    # The release tarball has no top-level directory.
    sourceRoot = ".";

    strictDeps = true;
    nativeBuildInputs = [autoPatchelfHook qt6.wrapQtAppsHook];
    # layer-shell-qt and qtwayland are needed for the Wayland overlay itself;
    # the rest satisfy the ELF NEEDED entries patched in by autoPatchelfHook.
    buildInputs = [
      qt6.qtbase
      qt6.qtwayland
      kdePackages.layer-shell-qt
      wayland
      libdeflate
      libglvnd
      (lib.getLib gcc-unwrapped)
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r usr/. $out/
      install -Dm644 ${licenseSrc} $out/share/licenses/omasnap/LICENSE
      runHook postInstall
    '';

    # omasnap resolves these by name at runtime; the wrapper keeps them in
    # the closure instead of relying on the session PATH.
    qtWrapperArgs = ["--prefix PATH : ${lib.makeBinPath runtimeDeps}"];

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      QT_QPA_PLATFORM=offscreen $out/bin/omasnap --version
      runHook postInstallCheck
    '';

    meta = {
      description = "Wayland screenshot and annotation overlay";
      homepage = "https://github.com/omacom/omasnap";
      license = lib.licenses.mit;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "omasnap";
      platforms = ["x86_64-linux"];
    };
  }
