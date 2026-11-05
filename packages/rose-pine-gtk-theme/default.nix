# rose-pine/gtk 2.2.0, carried locally because nixpkgs removed the package
# on 2026-07-22. The removed derivation's only GTK2-adjacent inputs
# (gtk-engine-murrine, gtk_engines, gnome-themes-extra) were buildInputs that
# its install phase never used: it installs the GTK3 theme trees and the GTK4
# CSS only. Reproduce that payload without the removed GTK2 dependencies.
{
  stdenvNoCC,
  lib,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation rec {
  pname = "rose-pine-gtk-theme";
  version = "2.2.0";

  src = fetchFromGitHub {
    owner = "rose-pine";
    repo = "gtk";
    tag = "v${version}";
    hash = "sha256-vCWs+TOVURl18EdbJr5QAHfB+JX9lYJ3TPO6IklKeFE=";
  };

  # Avoid the Makefile, which is only for theme maintainers.
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/themes/rose-pine{,-dawn,-moon}/gtk-4.0

    variants=("rose-pine" "rose-pine-dawn" "rose-pine-moon")
    for n in "''${variants[@]}"; do
      cp -r $src/gtk3/"''${n}"-gtk/* $out/share/themes/"''${n}"
      cp -r $src/gtk4/"''${n}".css $out/share/themes/"''${n}"/gtk-4.0/gtk.css
    done

    runHook postInstall
  '';

  meta = {
    description = "Rosé Pine theme for GTK";
    homepage = "https://github.com/rose-pine/gtk";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
