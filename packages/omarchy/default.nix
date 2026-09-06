# Omarchy v4 ("Quattro") shell environment — ADR-0007 Stage 2.
#
# Assembles an OMARCHY_PATH root from the pinned upstream source: the
# QuickShell plugin tree (shell/), the default shell.json (config/omarchy/),
# and the bin/ IPC wrappers. The upstream layout is preserved because the
# shell's QML builds paths as omarchyPath + "/bin/…", "/shell/…",
# "/default/…". Verified against the v4.0.2 reference install: nothing
# hardcodes /usr/share/omarchy, everything resolves through $OMARCHY_PATH.
#
# The entry scripts kebun invokes are wrapped with a store-path PATH prefix;
# the remaining upstream bin scripts are copied verbatim — but since the
# Stage 4 stack swap they are NOT inert: the shell's QML spawns them by name
# for widget data and IPC, so they are live runtime dependencies. Their
# upstream shebangs assume Arch (/bin/bash, /usr/bin/python3) and are
# rewritten to store paths below.
{
  pkgs,
  # The compositor's own hyprctl (the flake input), not nixpkgs'.
  hyprland ? pkgs.hyprland,
}: let
  inherit (pkgs) lib;

  omarchy-src = pkgs.fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy";
    # Lightweight tag v4.0.2 (2026-08-30). Bump deliberately; the tree is
    # byte-identical to the reference install audited 2026-09-01.
    rev = "346e69e1cec6c4e8924531874af6ba010a1bc99e";
    hash = "sha256-DtaDI3gyvK7YVnul2vRmNHHGK86Hn64WfbAVeG4888Y=";
  };

  runtimeDeps = with pkgs; [
    bash
    brightnessctl # omarchy-brightness-display
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    gpu-screen-recorder # omarchy-capture-screenrecording*
    hyprland
    inotify-tools
    jq
    libxkbcommon # xkbcli, keyname resolution in omarchy-menu-keybindings
    localsend # omarchy-menu-share / trigger.share.receive
    lua # omarchy-menu-keybindings' Lua-dofile cache step
    perl # omarchy-menu-select builds JSON with perl JSON::PP
    procps
    pulseaudio # pactl, needed by omarchy-audio-output-volume
    quickshell
    systemd
    util-linux
    wireplumber # wpctl, needed by omarchy-audio-input-mute
    xdg-terminal-exec # omarchy-launch-floating-terminal-with-presentation
    zbar # zbarimg, omarchy-capture-qr
  ];

  # Entry scripts (plus their repo-internal callees) that get wrapped.
  wrappedScripts = [
    "omarchy"
    "omarchy-shell"
    "omarchy-menu"
    "omarchy-osd"
    "omarchy-notification-send"
    "omarchy-system-lock"
    "omarchy-launch-shell"
    "omarchy-restart-shell"
    "omarchy-toggle"
    "omarchy-toggle-bar"
    "omarchy-toggle-idle"
    "omarchy-toggle-notification-silencing"
    "omarchy-cmd-present"
    "omarchy-hyprland-session-locked"
    "omarchy-plugin-list"
    # Stage 4 verbs kebun scripts call directly.
    "omarchy-menu-emoji"
    "omarchy-menu-clipboard"
    "omarchy-menu-select"
    "omarchy-menu-input"
    "omarchy-menu-keybindings"
    "omarchy-audio-output-volume"
    "omarchy-audio-output-switch"
    "omarchy-audio-input-mute"
    "omarchy-brightness-display"
    "omarchy-toggle-nightlight"
    "omarchy-notification-battery"
  ];
in
  pkgs.runCommand "omarchy-shell-env-4.0.2" {
    nativeBuildInputs = [pkgs.makeWrapper];
  } ''
    mkdir -p $out

    # Vendored upstream tree (clean tarball of the pinned rev).
    cp -a ${omarchy-src}/. $out/

    # cp -a preserves the read-only store modes of the fetched source; make
    # the copy mutable so the trim below can unlink.
    chmod -R u+w $out

    # Trim what NixOS never needs; keep the layout the shell reads:
    # shell/, bin/, config/, default/, themes/.
    rm -rf $out/.github $out/test $out/install $out/docs $out/manual $out/migrations

    chmod +x $out/bin/* 2>/dev/null || true

    # Upstream targets Arch, where /bin/bash and /usr/bin/python3 exist. NixOS
    # has no /bin, so the kernel ENOENTs on exec and every script dies with
    # "bad interpreter" — silently: the shell's QProcess reports "binary could
    # not be found", and a dead launcher produces no log at all. Rewrite the
    # shebangs across the whole tree (bin/, shell/ plugins, default/ helpers)
    # BEFORE wrapProgram: it relocates the original verbatim to .name-wrapped
    # and a broken shebang there survives the wrap. python3 needs PyGObject
    # for omarchy-file-select's D-Bus portal client.
    for f in $(grep -RIl '^#!/bin/bash' $out 2>/dev/null); do
      sed -i "1s|^#!/bin/bash|#!${pkgs.bash}/bin/bash|" "$f"
    done
    for f in $(grep -RIl '^#!/usr/bin/python3' $out 2>/dev/null); do
      sed -i "1s|^#!/usr/bin/python3|#!${pkgs.python3.withPackages (p: [p.pygobject3])}/bin/python3|" "$f"
    done

    # Wrap the entry scripts so their external commands resolve from the
    # closure, including repo-internal callees via $out/bin.
    for name in ${lib.concatStringsSep " " wrappedScripts}; do
      wrapProgram "$out/bin/$name" \
        --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDeps}"
    done
  ''
