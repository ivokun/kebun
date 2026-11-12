{
  config,
  lib,
  osConfig ? {},
  pkgs,
  inputs,
  username,
  system,
  ...
}: let
  # Laptop host capability from the NixOS side (kebun.host, set in
  # hosts/<name>/default.nix). The `or` guard keeps bare `nix eval` honest;
  # on the real host osConfig is always present.
  laptop = osConfig.kebun.host.isLaptop or false;
  # Steam's client payload is mutable user state; install an explicit recovery
  # command where Steam is enabled, without modifying that state on activation.
  steamEnabled = osConfig.programs.steam.enable or false;

  # Scripts get the compositor's own hyprctl (the pinned flake input, with the
  # lib/hyprland.nix compatibility overrides), not nixpkgs' pkgs.hyprland —
  # the versions drift and a mismatched client misleads scripts.
  scripts = import ../packages/scripts {
    inherit laptop pkgs;
    hyprland = import ../lib/hyprland.nix {inherit inputs system;};
  };

  # Same instantiation as home/features/omarchy-shell.nix, so this resolves to
  # the environment already installed — the `claude` wrapper uses its account
  # helper.
  omarchy = import ../packages/omarchy {
    inherit pkgs;
    hyprland = import ../lib/hyprland.nix {inherit inputs system;};
  };
  claudeCode = pkgs.callPackage ../packages/claude-code {};
  # Upstream routes a bare `claude` through its mise shim; kebun has no mise,
  # so install a wrapper that resolves Omarchy's active subscription account
  # and execs the real CLI (packages/claude-account).
  claudeAccount = pkgs.callPackage ../packages/claude-account {
    inherit omarchy;
    claude-code = claudeCode;
  };
in {
  nixpkgs.config.allowUnfree = true;

  home = {
    username = username;
    homeDirectory = "/home/${username}";
    stateVersion = "25.05";
  };

  # The generated Home Manager manpage currently creates an options.json
  # derivation with a discarded nixpkgs store context on this pinned HM/Nix
  # combination. The online manual remains available; avoid the unreliable
  # derivation until upstream fixes its context handling.
  manual.manpages.enable = false;

  # ─── Packages ───
  home.packages = with pkgs;
    [
      # CLI essentials
      eza
      bat
      fd
      ripgrep
      fzf
      btop
      nvtopPackages.amd
      fastfetch
      lazygit
      lazydocker
      atuin
      zoxide
      direnv
      nix-direnv

      # Download managers
      wget
      curl

      # Archive
      unzip
      p7zip

      # Networking
      tailscale
      # dig/nslookup — bind's dnsutils output. host(1) alone already arrives
      # via environment.corePackages (tasks/network-interfaces.nix).
      dnsutils

      # Security
      bitwarden-desktop
      age

      # Productivity
      obsidian
      typora

      # Communication
      signal-desktop
      slack
      telegram-desktop
      zoom-us

      # File sharing
      localsend

      # Browser
      brave
      google-chrome

      # Multimedia
      playerctl
      brightnessctl
      imv
      spotify
      obs-studio
      kdePackages.kdenlive

      # Dev tools
      gum
      tree
      tree-sitter

      # Documentation
      tldr

      # AI
      # Claude Code, re-pointed at a newer release (packages/claude-code) and
      # wrapped so a bare `claude` follows Omarchy's active subscription
      # account (packages/claude-account).
      claudeAccount
      inputs.luvus.packages.${system}.default
      # Official Linux beta repackaged from Anthropic's .deb (packages/claude-desktop)
      (pkgs.callPackage ../packages/claude-desktop {})

      # System info
      inxi

      # Remote access
      mosh

      # Nix helpers
      devenv
      nh
      nix-output-monitor

      # File manager
      nautilus

      # Screen utilities
      grim
      slurp
      swappy
      wl-clipboard

      # Misc
      jq
      file
      which

      # Image/media tools
      imagemagick
      ffmpegthumbnailer
      satty
      pinta

      # OCR
      tesseract

      # Calculator
      bc

      # Audio mixer
      wiremix

      # Wi-Fi TUI
      impala

      # Music player TUI
      cliamp

      # Office/productivity
      libreoffice
      evince

      # System utilities
      gnome-keyring
      libsecret
      socat
      xmlstarlet
      exfatprogs
      dosfstools
      bluetui
      iwd
      kdePackages.qtstyleplugin-kvantum

      # Security
      _1password-gui
      _1password-cli

      # Dictation
      hyprwhspr-rs

      # Cursor zoom
      hyprmag

      # Transcoding
      ffmpeg-headless

      # Custom scripts (laptop pieces gated on kebun.host.isLaptop via
      # lib.optionals, preserving the exact list order for laptop hosts)
    ]
    ++ (with scripts; [
      screenshot-edit
      wake-display
      color-picker
      window-pop
      check-updates
    ])
    ++ lib.optionals steamEnabled [
      scripts.steam-repair-bootstrap
    ]
    # Battery readouts (laptop only)
    ++ lib.optionals laptop [
      scripts.battery-remaining-time
    ]
    ++ (with scripts; [
      toggle-gaps
      toggle-layout
      toggle-power-profile
      wireguard-status
      wireguard-toggle
      launch-or-focus
      launch-tui
      launch-audio
      launch-wifi
      launch-bluetooth
      launch-activity

      # Menus
      menu-toggle
      menu-hardware
      menu-omarchy
      menu-background

      # Window & monitor management
      close-all-windows
      cycle-monitors
      cycle-monitor-scaling
      file-manager-cwd

      # Toggles
      toggle-single-window-square
    ])
    ++ lib.optionals laptop [
      # Laptop display management (laptop only)
      scripts.toggle-laptop-display
    ]
    ++ (with scripts; [
      toggle-mirror-display
    ])
    ++ lib.optionals laptop [
      # Lid-close handling (laptop only)
      scripts.lid-close
    ]
    ++ (with scripts; [
      # Media & capture
      localsend-share
      transcode

      # Info displays
      show-time
      show-weather
    ])
    ++ lib.optionals laptop [
      # Battery readout (laptop only)
      scripts.show-battery
    ]
    ++ (with scripts; [
      # Reminders
      reminder-set
      reminder-show
      reminder-clear

      # Dictation
      dictation-toggle
      dictation-ptt
      dictation-ptt-release

      # Cursor zoom
      cursor-zoom
      cursor-zoom-reset
    ]);

  # ─── Browser flags for Wayland ───
  # Chromium-family browsers read these from ~/.config/ (backlog §0.1 — they
  # lived under ~/config/ for years, so the flags never applied).
  home.file.".config/brave-flags.conf".text = ''
    --ozone-platform=wayland
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
  '';

  home.file.".config/chrome-flags.conf".text = ''
    --ozone-platform=wayland
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
  '';

  # ─── xdg-mime defaults ───
  xdg.mimeApps = {
    enable = true;
    # Some handlers (notably Neovim for XML) do not advertise these types.
    associations.added = config.xdg.mimeApps.defaultApplications;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "text/plain" = "nvim.desktop";
      # Cover Brave's advertised types explicitly so the desktop-entry cache
      # cannot select it as a fallback. Keep Brave available for manual use.
      "application/pdf" = "org.gnome.Evince.desktop";
      "image/gif" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/png" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "application/rdf+xml" = "nvim.desktop";
      "application/rss+xml" = "nvim.desktop";
      "application/xml" = "nvim.desktop";
      "text/xml" = "nvim.desktop";
      "application/xhtml+xml" = "google-chrome.desktop";
      "application/xhtml_xml" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/mailto" = "google-chrome.desktop";
      "x-scheme-handler/chromium" = "google-chrome.desktop";
      # claude-desktop deep links (desktop actions, auth callbacks)
      "x-scheme-handler/claude" = "com.anthropic.Claude.desktop";
    };
  };

  # ─── Home Manager itself ───
  programs.home-manager.enable = true;
}
