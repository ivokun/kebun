{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
  # ─── Hyprland ───
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    withUWSM = true;
  };

  # ─── XDG ───
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  # ─── Polkit ───
  security.polkit.enable = true;

  # ─── Dconf (needed for many GTK apps) ───
  programs.dconf.enable = true;

  # ─── Fonts ───
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.caskaydia-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
    ];

    fontconfig = {
      defaultFonts = {
        monospace = ["CaskaydiaMono Nerd Font" "Noto Sans Mono CJK JP"];
        sansSerif = ["Noto Sans CJK JP"];
        serif = ["Noto Serif CJK JP"];
      };
    };
  };

  # ─── Japanese Input (fcitx5 + Mozc) ───
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [ fcitx5-mozc ];
    };
  };
  # ─── Display-related services ───
  # GVfs for virtual filesystems (trash, mtp, etc.)
  services.gvfs.enable = true;

  # ─── Desktop packages (system-level) ───
  environment.systemPackages = with pkgs; [
    # Wayland essentials
    wl-clipboard
    grim
    slurp
    swappy
    brightnessctl

    # Screenshots and screen recording
    hyprpicker

    # Wallpaper
    swaybg

    # Notifications
    mako

    # App launcher
    inputs.walker.packages.${pkgs.system}.walker

    # Polkit authentication agent
    polkit_gnome

    # Polkit (already enabled above, but ensure package is available)
    polkit

    # Audio controls
    pamixer
    playerctl

    # Bluetooth
    bluez
    bluez-tools

    # File manager
    nautilus

    # Calculator
    gnome-calculator

    # Laptop power
    acpi

    # On-screen display for volume/brightness
    swayosd
  ];

  # ─── Bluetooth ───
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ─── D-Bus ───
  services.dbus.enable = true;

  # ─── SwayOSD Rose Pine Dawn theme ───
  environment.etc."swayosd/style.css".text = ''
    window {
      background: transparent;
    }
    
    .widget {
      background-color: #faf4ed;
      color: #575279;
      border: 2px solid #56949f;
      border-radius: 0;
      padding: 12px 20px;
    }
    
    .widget image {
      color: #56949f;
    }
    
    .widget progressbar trough {
      background-color: #f2e9e1;
      border-radius: 0;
    }
    
    .widget progressbar progress {
      background-color: #56949f;
      border-radius: 0;
    }
    
    .widget label {
      font-family: 'CaskaydiaMono Nerd Font';
      font-size: 14px;
    }
  '';

  # ─── Walker configuration ───
  environment.etc."walker/config.toml".text = ''
    # Walker app launcher configuration
    force_keyboard_focus = true
    selection_wrap = true
    
    [list]
    max_entries = 50
    
    [[providers]]
    name = "applications"
    weight = 5
    
    [[providers]]
    name = "websearch"
    prefix = "?"
    weight = 3
    
    [[providers]]
    name = "files"
    prefix = "~"
    weight = 2
    
    [[providers]]
    name = "symbols"
    prefix = ">"
    weight = 1
    
    [[providers]]
    name = "clipboard"
    prefix = "c"
    weight = 1
  '';
}
