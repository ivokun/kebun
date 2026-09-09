# Claude Desktop — the official Linux beta app, repackaged from Anthropic's
# .deb for NixOS. https://code.claude.com/docs/en/desktop-linux
#
# Strategy: extract data.tar.xz and run the vendored Electron binary inside a
# buildFHSEnv bubblewrap root that supplies the FHS layout the deb expects
# (the same pattern as nixpkgs' vscode wrapper). No patchelf: /lib64's loader
# and every dynamic dependency resolve inside the env, and bwrap keeps
# /nix/store bound so the nix-built Cowork tools run unmodified.
#
# Cowork (the QEMU/KVM VM tab) is wired here + in hosts/common:
#   - qemu-system-x86_64 + virtiofsd land on the env's /usr/bin, and
#     /usr/libexec/virtiofsd is symlinked in (the app's preferred lookup path)
#   - OVMF firmware is symlinked at /usr/share/OVMF — the app's hardcoded
#     lookup path. nixpkgs' OVMFFull ships the 2M pair (OVMF_CODE.fd +
#     OVMF_VARS.fd); the app tries OVMF_CODE_4M.fd first and falls back.
#   - /dev/kvm + /dev/vhost-vsock come from the host: the kvm group
#     (hosts/common/users.nix) and boot.kernelModules vhost_vsock
#     (hosts/common/core.nix).
#
# Updates: bump `version` and re-fetch the hash —
#   nix store prefetch-file \
#     https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_<ver>_amd64.deb
# (newest version is in the repo's Packages index; the app does not
# self-update on Linux.)
{
  lib,
  stdenv,
  fetchurl,
  buildFHSEnv,
  symlinkJoin,
  # Electron runtime libraries — mirrors the deb's Depends list; the set is
  # patterned after nixpkgs' vscode FHS wrapper. NOTE: the FHS root links only
  # these outputs, not their dependency closures, so anything the app or its
  # bundled libs dlopen must be listed explicitly.
  gtk3,
  glib,
  dbus,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  pango,
  gdk-pixbuf,
  cups,
  expat,
  alsa-lib,
  libgbm,
  mesa,
  udev,
  nss,
  nspr,
  libsecret,
  libnotify,
  libuuid,
  libxkbcommon,
  xkeyboard-config,
  zlib,
  fontconfig,
  freetype,
  tzdata,
  wayland,
  xdg-utils,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  # CLIs the app probes by FHS name (git/ssh for repo sync, pgrep for
  # process checks)
  git,
  openssh,
  procps,
  # Cowork VM
  qemu_kvm,
  virtiofsd,
  OVMFFull,
}: let
  pname = "claude-desktop";
  version = "1.19367.0";

  # The raw Electron tree from the official deb. The deb's maintainer scripts
  # (postinst: apt-repo registration + AppArmor profile) are deliberately not
  # executed — they are Debian machinery and make no sense in the store.
  unwrapped = stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
      hash = "sha256-dvVwcwwRhZJOJCPF+IonvsF8HnrbBV7NCUAaDpOpKZs=";
    };

    # A deb is an ar archive holding data.tar.xz — stdenv's ar/xz/tar unpack
    # it without pulling in dpkg.
    buildCommand = ''
      mkdir deb && cd deb
      ar x $src
      mkdir data
      tar -xJf data.tar.xz -C data

      # Electron app dir: the 217M main binary plus resources/ (Cowork
      # helper, bundled virtiofsd, smol VM disk image).
      mkdir -p $out/lib
      cp -r data/usr/lib/claude-desktop $out/lib/

      # Desktop integration as shipped. Exec=claude-desktop is satisfied by
      # the FHS wrapper's bin (below); StartupWMClass is com.anthropic.Claude,
      # which the omarchy shell's focus matching keys off.
      mkdir -p $out/share/applications $out/share/icons
      cp data/usr/share/applications/*.desktop $out/share/applications/
      cp -r data/usr/share/icons/hicolor $out/share/icons/
    '';

    # Vendored Chromium binary — leave it byte-identical.
    dontStrip = true;
    dontPatchELF = true;
  };

  fhs = buildFHSEnv {
    inherit pname version;

    targetPkgs = pkgs:
      with pkgs; [
        # GTK stack
        gtk3
        glib
        dbus
        at-spi2-atk
        at-spi2-core
        cairo
        pango
        gdk-pixbuf

        # X11 / Wayland
        libx11
        libxcb
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
        libxtst
        libxkbcommon
        xkeyboard-config # libxkbcommon dlopens /usr/share/X11/xkb
        wayland

        # Rendering
        mesa # EGL + DRI drivers
        libgbm

        # Misc runtime
        cups
        expat
        alsa-lib
        udev
        nss
        nspr
        libsecret
        libnotify
        libuuid
        zlib
        fontconfig
        freetype
        tzdata # the Cowork helper reads /usr/share/zoneinfo
        xdg-utils

        # CLIs the app probes by FHS name
        git
        openssh
        procps

        # Cowork VM
        qemu_kvm
        virtiofsd
      ];

    # Cowork's hardcoded FHS-path lookups (see header comment). These must be
    # symlinks inside the rootfs itself — extraBwrapArgs can't mkdir into the
    # read-only-bound /usr.
    extraBuildCommands = ''
      mkdir -p $out/usr/libexec
      ln -s ${virtiofsd}/bin/virtiofsd $out/usr/libexec/virtiofsd
      # the .fd files live in the FV/ subdir of the OVMF output; the app
      # wants them directly under /usr/share/OVMF
      ln -s ${lib.getOutput "fd" OVMFFull}/FV $out/usr/share/OVMF
    '';

    # The env's /etc/profile is sourced before exec (realInit).
    profile = ''
      # Native Wayland with X11 fallback (Electron 28+).
      export ELECTRON_OZONE_PLATFORM_HINT=auto
    '';

    # IME flags mirror the browser flags in home/common.nix — fcitx5/Mozc
    # input needs them under native Wayland.
    runScript = "${unwrapped}/lib/claude-desktop/claude-desktop --enable-wayland-ime --wayland-text-input-version=3";
  };
in
  # Join the bwrap launcher (bin/) with the deb's desktop entry + icons
  # (share/), so one package serves PATH, the app grid and the omarchy
  # shell's app search.
  symlinkJoin {
    name = "${pname}-${version}";
    paths = [
      fhs
      unwrapped
    ];

    meta = {
      description = "Desktop application for Claude.ai (Linux beta)";
      homepage = "https://claude.ai";
      license = lib.licenses.unfree;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "claude-desktop";
      platforms = ["x86_64-linux"];
    };
  }
