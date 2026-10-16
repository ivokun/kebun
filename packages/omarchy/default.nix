# Omarchy v4 ("Quattro") shell environment — ADR-0007 Stage 2.
#
# Assembles an OMARCHY_PATH root from the pinned upstream source: the
# QuickShell plugin tree (shell/), the default shell.json (config/omarchy/),
# and the bin/ IPC wrappers. The upstream layout is preserved because the
# shell's QML builds paths as omarchyPath + "/bin/…", "/shell/…",
# "/default/…". Verified against the v4.0.2 reference install: nothing
# hardcodes /usr/share/omarchy, everything resolves through $OMARCHY_PATH.
# (Post-v4.0.2 QML also probes /usr/share/omarchy-platform/*.json; absent on
# NixOS, which upstream treats as "no platform overrides".)
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
    # quattro HEAD 8a787b6 (2026-10-15), 953 commits past v4.0.2. Not a tag:
    # v4.0.3/v4.0.4 live on a release branch that lacks the shell security
    # fixes kebun runs (screen-recording state out of /tmp, notification
    # sanitization, plugin capability restrictions, display panel
    # escaping). Bump deliberately.
    rev = "8a787b6a8bec830b04543bf14c760ee0a10591f6";
    hash = "sha256-G+63CTcIO6cf4xShEqxaB6jT7XJlbObhXEQI0DNHMlY=";
  };

  # PyGObject for omarchy-file-select's D-Bus portal client and the input
  # method indicator's Fcitx D-Bus reader.
  python = pkgs.python3.withPackages (p: [p.pygobject3]);

  runtimeDeps = with pkgs; [
    bash
    bluez # bluetoothctl, omarchy-bluetooth-device/power
    brightnessctl # omarchy-brightness-display
    coreutils
    # dbus-monitor (omarchy-system-sleep-monitor's PrepareForSleep listener)
    # and busctl (omarchy-system-sleep-lock's InhibitDelayMaxUSec probe)
    dbus
    ffmpeg-headless # omarchy-capture-screenrecording thumbnails + finalize pass (ffmpeg/ffprobe)
    findutils
    gawk
    gnugrep
    gnused
    # Recorder binary; modules/aspects/desktop.nix enables the NixOS module
    # separately so gsr-kms-server also gets its required capability wrapper.
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
    tailscale # omarchy-tailscale-receive / -send (Taildrop)
    tesseract # omarchy-capture-text (OCR)
    util-linux
    v4l-utils # v4l2-ctl, omarchy-capture-webcam-list/resolution probing
    wireplumber # wpctl, needed by omarchy-audio-input-mute
    wl-clipboard # wl-copy, omarchy-capture-screenshot/text/qr
    xdg-utils # xdg-open, omarchy-tailscale-receive's click-to-open notification
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
    # Pre-suspend locking (upstream Omarchy v4.0.2 parity): the monitor holds
    # a delay inhibitor on PrepareForSleep and the lock script secures the
    # session before the window expires (home/features/sleep-lock.nix starts
    # the monitor). dbus-monitor / busctl / systemd-inhibit resolve from
    # runtimeDeps above.
    "omarchy-system-sleep-monitor"
    "omarchy-system-sleep-lock"
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
    # Bluetooth panel actions — the QML spawns these by name (toggle, pair,
    # connect, disconnect, forget); unwrapped they depend on bluetoothctl and
    # rfkill happening to sit on the session PATH.
    "omarchy-bluetooth-device"
    "omarchy-bluetooth-power"
    "omarchy-restart-bluetooth"
    # Tailscale bar widget (omarchy.tailscale): the panel spawns -send by
    # name for Taildrop, and home/features/tailscale-receive.nix runs
    # -receive as a user service that saves incoming files to ~/Downloads.
    "omarchy-tailscale-send"
    "omarchy-tailscale-receive"
  ];
in
  pkgs.runCommand "omarchy-shell-env-4.0.4-unstable-2026-10-15" {
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
    # and a broken shebang there survives the wrap.
    #
    # On top of shebang fixes, kebun divergence patches in patches/ are
    # applied (network panel iwd fallback, recording output dir).
    for f in $(grep -RIl '^#!/bin/bash' $out 2>/dev/null); do
      sed -i "1s|^#!/bin/bash|#!${pkgs.bash}/bin/bash|" "$f"
    done
    for f in $(grep -RIl '^#!/usr/bin/python3' $out 2>/dev/null); do
      sed -i "1s|^#!/usr/bin/python3|#!${python}/bin/python3|" "$f"
    done
    # The keyboard widget's input-method singleton execs python by absolute
    # path (not a shebang) and respawns it every 5s when the exec fails.
    substituteInPlace $out/shell/Commons/InputMethodState.qml \
      --replace-fail '"/usr/bin/python3"' '"${python}/bin/python3"'
    # NixOS has no /usr/share/zoneinfo; the Elsewhen panel's city search
    # reads the zone table directly.
    substituteInPlace $out/shell/plugins/panels/elsewhen/Panel.qml \
      --replace-fail '"/usr/share/zoneinfo/zone1970.tab"' '"${pkgs.tzdata}/share/zoneinfo/zone1970.tab"'

    # Kebun divergence patches on top of the pinned upstream tree. The network
    # panel's connection state has no iwd backend in Quickshell (ADR-0012), so
    # fall back to omarchy-network-status's script data and offer impala as the
    # panel's Wi-Fi management affordance. The screen recording output
    # directory is created on first use for fresh installs. (Upstream now
    # matches the recorder by /proc/<pid>/exe basename, which nixpkgs'
    # bin/.wrapped/gpu-screen-recorder satisfies, so no process-match patch.)
    patch -d $out -p1 < ${./patches/network-iwd-state.patch}
    patch -d $out -p1 < ${./patches/network-impala-button.patch}
    patch -d $out -p1 < ${./patches/screenrecord-create-output-dir.patch}

    # Wrap the entry scripts so their external commands resolve from the
    # closure, including repo-internal callees via $out/bin.
    for name in ${lib.concatStringsSep " " wrappedScripts}; do
      wrapProgram "$out/bin/$name" \
        --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDeps}"
    done
  ''
