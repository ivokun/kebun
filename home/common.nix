{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  scripts = import ../packages/scripts {inherit pkgs;};
in {
  nixpkgs.config.allowUnfree = true;

  home = {
    username = username;
    homeDirectory = "/home/${username}";
    stateVersion = "25.05";
  };

  # ─── Packages ───
  home.packages = with pkgs; [
    # CLI essentials
    eza
    bat
    fd
    ripgrep
    fzf
    btop
    fastfetch
    lazygit
    lazydocker
    starship
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

    # Security
    bitwarden-desktop
    age

    # Productivity
    obsidian

    # Communication
    signal-desktop
    slack
    telegram-desktop

    # Browser
    brave

    # Multimedia
    playerctl
    pamixer
    brightnessctl
    imv

    # Dev tools
    gum
    tree

    # System info
    inxi

    # Remote access
    mosh

    # Nix helpers
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
    mpv

    # Office/productivity
    libreoffice-fresh
    evince

    # System utilities
    gnome-keyring
    libsecret
    plocate
    socat
    xmlstarlet
    exfatprogs
    dosfstools

    # Security
    _1password-gui
    _1password-cli

    # Custom scripts
  ] ++ (with scripts; [
    screenshot
    screenshot-clipboard
    volume-toggle
    brightness-toggle
    lock-screen
    toggle-waybar
    toggle-nightlight
    restart-waybar
    restart-walker
    color-picker
    window-pop
    check-updates
    screenrecord
    audio-switch
  ]);

  # ─── Browser flags for Wayland ───
  home.file."config/brave-flags.conf".text = ''
    --ozone-platform=wayland
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
  '';

  programs.chromium = {
    enable = true;
    commandLineArgs = [
      "--ozone-platform=wayland"
      "--ozone-platform-hint=wayland"
      "--enable-features=WaylandWindowDecorations,TouchpadOverscrollHistoryNavigation"
      "--enable-wayland-ime"
      "--oauth2-client-id=77185425430.apps.googleusercontent.com"
      "--oauth2-client-secret=OTJgUOQcT7lO7GsGZq2G4IlT"
      "--disable-features=WaylandWpColorManagerV1"
    ];
  };

  # ─── xdg-mime defaults ───
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium-browser.desktop";
      "text/plain" = "nvim.desktop";
      "x-scheme-handler/http" = "chromium-browser.desktop";
      "x-scheme-handler/https" = "chromium-browser.desktop";
      "x-scheme-handler/mailto" = "chromium-browser.desktop";
    };
  };

  # ─── Home Manager itself ───
  programs.home-manager.enable = true;
}
