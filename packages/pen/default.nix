# Pen (pen.dev, formerly Pencil) — the agentic design canvas's Electron
# desktop app, wrapped from upstream's x86_64 AppImage.
#
# Source: the versioned GitHub release asset, not pen.dev/download/… — that
# URL is unversioned (it 302s to a short-lived signed GCS link that always
# serves the newest build), so a fixed hash on it breaks on every upstream
# release. The two are byte-identical for a given version.
#
# appimageTools.wrapType2 supplies the FHS runtime; the in-app updater
# (electron-updater, GitHub provider) is inert because $APPIMAGE is unset in
# the wrapper, so the version is whatever this file pins. The session-wide
# ELECTRON_OZONE_PLATFORM_HINT (home/features/hyprland.nix) puts it on
# Wayland; no flags needed here.
#
# Updates: `gh release list -R highagency/pen-desktop-releases -L 1`, then
# take the sha512 for the x86_64 AppImage from that release's
# latest-linux.yml —
#   gh release download v<ver> -R highagency/pen-desktop-releases -p latest-linux.yml -O -
# and bump `version` + `hash` together.
{
  lib,
  appimageTools,
  fetchurl,
}: let
  pname = "pen";
  version = "1.2.21";

  src = fetchurl {
    url = "https://github.com/highagency/pen-desktop-releases/releases/download/v${version}/Pen-${version}-linux-x86_64.AppImage";
    hash = "sha512-Q6an38PwcaqLEqoqisi3mFmQRgGEYi4881wwHhYuYcYDPZr1woe3m3rRMUQqof2yTZKuTxGJfgv9nXtWi/od9w==";
  };

  contents = appimageTools.extract {inherit pname version src;};
in
  appimageTools.wrapType2 {
    inherit pname version src;

    # The launcher is pen-desktop: `pen` belongs to the CLI (./cli.nix),
    # which upstream docs and agents invoke by that name. The AppImage's
    # entry targets its own AppRun; point it at the renamed wrapper.
    # --no-sandbox is upstream's: the bundled chrome-sandbox can't be setuid
    # from the store.
    extraInstallCommands = ''
      mv $out/bin/${pname} $out/bin/pen-desktop
      install -Dm444 ${contents}/pen.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/pen.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=pen-desktop'
      install -Dm444 ${contents}/usr/share/icons/hicolor/512x512/apps/pen.png \
        -t $out/share/icons/hicolor/512x512/apps
    '';

    meta = {
      description = "Agentic design canvas for .pen files (desktop app)";
      homepage = "https://pen.dev";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = ["x86_64-linux"];
      mainProgram = "pen-desktop";
    };
  }
