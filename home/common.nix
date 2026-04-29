{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  scripts = import ../../packages/scripts {inherit pkgs;};
in {
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
    mise
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

    # Custom scripts
  ] ++ (with scripts; [
    screenshot
    volume-toggle
    brightness-toggle
    lock-screen
    toggle-waybar
    toggle-nightlight
  ]);

  # ─── xdg-mime defaults ───
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "text/plain" = "nvim.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/mailto" = "brave-browser.desktop";
    };
  };

  # ─── Home Manager itself ───
  programs.home-manager.enable = true;
}
