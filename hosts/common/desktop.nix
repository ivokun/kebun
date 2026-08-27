{
  config,
  lib,
  pkgs,
  inputs,
  username,
  ...
}: let
  # Script to unlock LUKS devices using the password provided by PAM.
  #
  # IMPORTANT: You must first add your login password as a LUKS key
  # for each device you want to unlock on login:
  #
  #   sudo cryptsetup luksAddKey /dev/disk/by-uuid/5525027e-a087-470e-a530-3ab692f4a14c
  #   sudo cryptsetup luksAddKey /dev/disk/by-uuid/e1906a9e-c934-4352-bfea-02620b6abd80
  #
  # This provides a password fallback in case TPM2 auto-unlock fails,
  # and ensures your login password can unlock LUKS "when logged in as well".
  unlockLuksOnLogin = pkgs.writeShellScript "unlock-luks-on-login" ''
    set -euo pipefail

    # Read password from stdin (PAM exposes it via expose_authtok)
    IFS= read -r password

    # Try to unlock root device if not already open
    if [ ! -e "/dev/mapper/luks-5525027e-a087-470e-a530-3ab692f4a14c" ]; then
      printf '%s' "$password" | ${pkgs.cryptsetup}/bin/cryptsetup open \
        /dev/disk/by-uuid/5525027e-a087-470e-a530-3ab692f4a14c \
        luks-5525027e-a087-470e-a530-3ab692f4a14c 2>/dev/null || true
    fi

    # Try to unlock swap device if not already open
    if [ ! -e "/dev/mapper/luks-e1906a9e-c934-4352-bfea-02620b6abd80" ]; then
      printf '%s' "$password" | ${pkgs.cryptsetup}/bin/cryptsetup open \
        /dev/disk/by-uuid/e1906a9e-c934-4352-bfea-02620b6abd80 \
        luks-e1906a9e-c934-4352-bfea-02620b6abd80 2>/dev/null || true
    fi
  '';
in {
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
      addons = with pkgs; [fcitx5-mozc];
    };
  };
  # ─── Display-related services ───
  # GVfs for virtual filesystems (trash, mtp, etc.)
  services.gvfs.enable = true;

  # ─── Secret storage ───
  # gnome-keyring and libsecret were installed as bare packages, so anything
  # storing a secret (Chrome/Brave passwords, libsecret consumers) had no
  # running daemon to talk to. The PAM hook is the other half: it unlocks the
  # keyring with the login password at greeter time, otherwise the daemon
  # starts locked and prompts on first use.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # ─── Display Manager ───
  # Using SDDM (like Omarchy) instead of GDM for a cleaner Wayland experience.
  # Wayland support is enabled so the greeter runs natively on Wayland.
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;

    # Minimal, clean theme that matches a modern Wayland desktop
    theme = "where_is_my_sddm_theme";

    # Auto-login for single-user setup: skip greeter on boot, but still
    # show it when logging out (so both experiences look the same).
    settings = {
      Autologin = {
        User = username;
        Session = "hyprland";
      };
    };
  };

  # Default to Hyprland UWSM session in SDDM
  services.displayManager.defaultSession = "hyprland";

  # ─── PAM LUKS Integration ───
  # Unlock LUKS devices on login using the provided password.
  # Works as a fallback when TPM2 auto-unlock is unavailable.
  # Configured for both SDDM and TTY (login) sessions.
  security.pam.services.sddm.rules.auth.luksUnlock = {
    order = 1100;
    control = "optional";
    modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
    args = ["expose_authtok" "${unlockLuksOnLogin}"];
  };

  security.pam.services.login.rules.auth.luksUnlock = {
    order = 1100;
    control = "optional";
    modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
    args = ["expose_authtok" "${unlockLuksOnLogin}"];
  };

  # ─── Hyprlock PAM stack ───
  # Without this there is no /etc/pam.d/hyprlock, and hyprlock falls back to
  # /etc/pam.d/su ("Pam module ... does not exist! Falling back to su") — the
  # wrong stack to authenticate a screen unlock against.
  security.pam.services.hyprlock = {};

  # ─── Desktop packages (system-level) ───
  environment.systemPackages = with pkgs; [
    # SDDM theme (must be in systemPackages for /run/current-system/sw/share/sddm/themes)
    where-is-my-sddm-theme

    # UWSM (explicitly ensure uwsm is in PATH for .zprofile)
    uwsm

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

    # App launcher (backend enabled via services.elephant below)
    walker

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

  # ─── Walker configuration ───
  #
  # Elephant is walker's provider backend — walker 2.x is only a frontend and
  # refuses to start without it. Every provider (apps, calc, clipboard, …) lives
  # on this side, so without it SUPER+SPACE does nothing at all.
  services.elephant.enable = true;

  # Must live under xdg/, i.e. /etc/xdg/walker. Plain /etc/walker is not on
  # XDG_CONFIG_DIRS, so walker silently never reads it.
  #
  # This is walker 2.x schema; walker merges it over its own defaults, so the
  # upstream provider actions and prefixes (">" runner, "/" files, "." symbols,
  # ":" clipboard, "@" websearch, "=" calc) stay in place.
  environment.etc."xdg/walker/config.toml".text = ''
    force_keyboard_focus = true
    selection_wrap = true

    [providers]
    default = ["desktopapplications", "calc", "websearch"]
    empty = ["desktopapplications"]
    max_results = 50
  '';
}
