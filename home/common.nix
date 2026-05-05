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
  home.packages = with pkgs;
    [
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
      typora

      # Communication
      signal-desktop
      slack
      telegram-desktop

      # File sharing
      localsend

      # Browser
      brave
      google-chrome

      # Multimedia
      playerctl
      pamixer
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
      claude-code

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
      bluetui
      thermald
      iwd
      kvantum

      # Security
      _1password-gui
      _1password-cli

      # Custom scripts
    ]
    ++ (with scripts; [
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
      check-waybar-updates
      screenrecord
      audio-switch
    ]);

  # ─── Browser flags for Wayland ───
  home.file."config/brave-flags.conf".text = ''
    --ozone-platform=wayland
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
  '';

  home.file."config/chrome-flags.conf".text = ''
    --ozone-platform=wayland
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
  '';

  # ─── xdg-mime defaults ───
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "text/plain" = "nvim.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/mailto" = "google-chrome.desktop";
    };
  };

  # ─── Home Manager itself ───
  programs.home-manager.enable = true;
}
