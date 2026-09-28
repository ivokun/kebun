# Electron 44.4.3 binary — the version packages/desktop declares at upstream
# tag v2.0.18. Ported from upstream's nix/electron.nix with the version
# hardcoded (kebun's vendored tree is a fetchFromGitHub checkout, not a
# relative source tree) and hash-checked against Electron's SHASUMS256.txt
# for v44.4.3. The pinned nixpkgs electron scope tops out at 43, so this
# derivation is built in-tree.
{
  alsa-lib,
  at-spi2-atk,
  cairo,
  callPackage,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  lib,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxkbfile,
  libxrandr,
  libxshmfence,
  nss,
  nspr,
  pango,
  path,
  pciutils,
  pipewire,
  speechd-minimal,
  stdenv,
  systemd,
  vulkan-loader,
}: let
  version = "44.4.3";

  electronLibPath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    gtk4
    nss
    nspr
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxkbfile
    pango
    pciutils
    stdenv.cc.cc
    systemd
    libnotify
    pipewire
    libsecret
    libpulseaudio
    speechd-minimal
    libdrm
    libgbm
    libxkbcommon
    libxshmfence
    libGL
    vulkan-loader
  ];
in let
  base =
    callPackage (path + "/pkgs/development/tools/electron/binary/generic.nix") {}
    version {
      # electron-v44.4.3-linux-{x64,arm64}.zip from SHASUMS256.txt.
      x86_64-linux = "fe880a7e37160cfd4e00193bc4c713ead7a778abfe74860a2d36d86fd0be48a8";
      aarch64-linux = "61f084a5ac0f1835efc12b9db17042d92c8c617b03578f96a888acd4a05a0b10";
      # fetchzip hashes the unpacked headers, not the release tarball.
      headers = "sha256-QPkX+99kArlQhhbgOZe+Hsk28G5cadkUy0G0cIDtEh8=";
    };
in
  base.overrideAttrs (_old: {
    # Electron ≥43 no longer bundles the libEGL/libGLESv2 (libANGLE) shared
    # libraries in the Linux zip, but the pinned generic.nix patchelfs them
    # unconditionally — the unmatched lib*GL* glob collapses to an empty file
    # list and patchelf aborts with "missing filename". Patch only what the
    # zip actually ships; keep the rest of the postFixup semantics in sync
    # with the pinned generic.nix.
    postFixup = ''
      patchelf \
        --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        --set-rpath "${electronLibPath}:$out/libexec/electron" \
        $out/libexec/electron/electron \
        $out/libexec/electron/chrome_crashpad_handler

      for f in $out/libexec/electron/lib*GL*; do
        [ -e "$f" ] || continue
        patchelf \
          --set-rpath "${
        lib.makeLibraryPath [
          libGL
          pciutils
          vulkan-loader
        ]
      }" \
          "$f"
      done

      # replace bundled vulkan-loader
      rm "$out/libexec/electron/libvulkan.so.1"
      ln -s -t "$out/libexec/electron" "${lib.getLib vulkan-loader}/lib/libvulkan.so.1"
    '';
  })
