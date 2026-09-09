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
    ffmpeg-headless # omarchy-capture-screenrecording thumbnails + finalize pass (ffmpeg/ffprobe)
    findutils
    gawk
    gnugrep
    gnused
    gpu-screen-recorder # omarchy-capture-screenrecording*
    grim # omarchy-capture-screenshot/text/qr
    hyprland
    hyprpicker # omarchy-capture-region's screen freeze (and capture color picker)
    inotify-tools
    iw # omarchy-network-status reads SSID/signal/freq via `iw dev … link`
    iproute2 # omarchy-network-status resolves the default-route interface
    iputils # omarchy-network-status pings gateway/internet for latency
    jq
    libxkbcommon # xkbcli, keyname resolution in omarchy-menu-keybindings
    localsend # omarchy-menu-share / trigger.share.receive
    lua # omarchy-menu-keybindings' Lua-dofile cache step
    # mpv-unwrapped, NOT mpv: plain pkgs.mpv wraps yt-dlp, which builds-depends
    # on deno — and flake.nix's deno overlay (skipped flaky test) rehashes it,
    # so every rebuild would compile deno from source (~1h on sakura). The
    # webcam overlay and notification click-to-play only need local playback.
    mpv-unwrapped
    perl # omarchy-menu-select builds JSON with perl JSON::PP
    procps
    pulseaudio # pactl, needed by omarchy-audio-output-volume
    quickshell
    slurp # omarchy-capture-region
    systemd
    tesseract # omarchy-capture-text (OCR)
    util-linux
    v4l-utils # v4l2-ctl, omarchy-capture-webcam-list/resolution probing
    wireplumber # wpctl, needed by omarchy-audio-input-mute
    wl-clipboard # wl-copy, omarchy-capture-screenshot/text/qr
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
    # Network panel data — the shell's QML spawns it by name on a timer, and
    # its iw/ip/ping/jq calls must resolve from the closure, not session PATH
    # (the panel patches derive bar/panel state from this script's output).
    "omarchy-network-status"
    # Capture pipeline (upstream parity — backlog item 15): the PRINT /
    # ALT+PRINT / SUPER+CTRL+PRINT binds and the shell's capture menu routes
    # spawn these by name. The hyprpicker freeze + smart slurp picker live in
    # omarchy-capture-region; gpu-screen-recorder is the recording backend.
    "omarchy-capture-screenshot"
    "omarchy-capture-region"
    "omarchy-capture-text"
    "omarchy-capture-qr"
    "omarchy-capture-screenrecording"
    "omarchy-capture-screenrecording-with-webcam"
    "omarchy-capture-webcam-list"
    "omarchy-capture-webcam-resize"
    "omarchy-hyprland-monitor-focused"
    # Menu `when` clause for the webcam screenrecord route.
    "omarchy-hw-webcam"
  ];
in
  pkgs.runCommand "omarchy-shell-env-4.0.2" {
    nativeBuildInputs = [pkgs.makeWrapper pkgs.patch];
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
    #
    # On top of shebang fixes, kebun divergence patches in patches/ are
    # applied (currently: network panel iwd state fallback — see ADR-0012).
    for f in $(grep -RIl '^#!/bin/bash' $out 2>/dev/null); do
      sed -i "1s|^#!/bin/bash|#!${pkgs.bash}/bin/bash|" "$f"
    done
    for f in $(grep -RIl '^#!/usr/bin/python3' $out 2>/dev/null); do
      sed -i "1s|^#!/usr/bin/python3|#!${pkgs.python3.withPackages (p: [p.pygobject3])}/bin/python3|" "$f"
    done

    # Kebun divergence patches on top of the pinned upstream tree (ADR-0012):
    # the network panel's connection state has no iwd backend in Quickshell,
    # so fall back to omarchy-network-status's script data; also offer an
    # impala launcher as the panel's Wi-Fi management affordance.
    patch -d $out -p1 < ${./patches/network-iwd-state.patch}
    patch -d $out -p1 < ${./patches/network-impala-button.patch}

    # Wrap the entry scripts so their external commands resolve from the
    # closure, including repo-internal callees via $out/bin.
    for name in ${lib.concatStringsSep " " wrappedScripts}; do
      wrapProgram "$out/bin/$name" \
        --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDeps}"
    done
  ''
