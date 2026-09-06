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

  # Vendored Omarchy env (pinned upstream tree), reused by the SDDM theme and
  # greeter compositor config below — same store path the shell already
  # imports, so nothing is rebuilt twice.
  omarchyEnv = import ../../packages/omarchy {
    inherit pkgs;
    hyprland = inputs.hyprland.packages.${pkgs.system}.hyprland;
  };

  # Single-sourced Rose Pine Dawn palette (same file the shell theme renders
  # from) — the greeter skims its colors from here.
  palette = import ../../lib/palette.nix;

  # SDDM greeter theme: the vendored upstream Omarchy theme re-skinned at
  # build time with the kebun palette (single-sourced from lib/palette.nix):
  # light-mode Dawn background, Dawn-text assets (the upstream PNGs are Tokyo
  # Night), and the omarchy logo replaced by an IVOKUN wordmark in the accent
  # color. The failed-state assets keep their semantics in Dawn red.
  sddmThemeOmarchy = let
    im = pkgs.imagemagick;
  in
    pkgs.runCommand "sddm-theme-omarchy-kebun" {} ''
      mkdir -p $out/share/sddm/themes
      cp -r ${omarchyEnv}/default/sddm/omarchy $out/share/sddm/themes/omarchy
      chmod -R u+w $out/share/sddm/themes/omarchy
      cd $out/share/sddm/themes/omarchy

      # Light mode: Dawn base replaces the Tokyo Night background.
      substituteInPlace Main.qml --replace '#1a1b26' '${palette.background}'

      # Recolor assets channel-wise (RGB only), preserving alpha: bullet,
      # lock and the entry frame go Tokyo Night fg → Dawn text; failed
      # states go Tokyo Night red → Dawn love.
      for f in bullet.png lock.png entry.png; do
        ${im}/bin/convert $f -channel RGB -fill '${palette.foreground}' -opaque '#C0CAF5' $f
      done
      for f in lock-failed.png entry-failed.png; do
        ${im}/bin/convert $f -channel RGB -fill '${palette.red}' -opaque '#F7768E' $f
      done

      # IVOKUN wordmark — the shared derivation also used by the Plymouth
      # splash, so boot and login show the identical logo.
      cp ${pkgs.callPackage ../../packages/ivokun-wordmark {}}/logo.png logo.png
    '';

  # The upstream greeter config + kebun's input delta. The greeter session
  # does not inherit the desktop input config (its kb_layout defaults to us),
  # and the layout mismatch caused failed logins for symbol-heavy passwords.
  # Split into two derivations: a shell heredoc would be mangled by nix fmt.
  sddmGreeterDelta = pkgs.writeText "sddm-greeter-kebun-delta.lua" ''

    -- Kebun: JP keyboard layout — the greeter session does not inherit the
    -- desktop input config, and a layout mismatch caused failed logins.
    hl.config({
      input = {
        kb_layout = "jp",
      },
    })
  '';

  sddmGreeterHyprland = pkgs.runCommand "sddm-greeter-hyprland" {} ''
    mkdir -p $out
    # Fresh redirect, not cp: store sources are read-only (mode 444) and cp
    # preserves that, which breaks the append below.
    { cat ${omarchyEnv}/default/sddm/hyprland.lua; cat ${sddmGreeterDelta}; } > $out/hyprland.lua
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
      nerd-fonts.jetbrains-mono # SDDM omarchy theme's font family
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
  # The greeter uses the vendored upstream Omarchy theme (default/sddm/
  # omarchy) — staged via sddmThemeOmarchy into environment.systemPackages,
  # since SDDM discovers themes in XDG data dirs. Its font family
  # (JetBrainsMono Nerd Font) is in system fonts above.
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "omarchy";

    # Run the greeter under Hyprland, like upstream's sddm.sh — the omarchy
    # theme is designed against it; the module's Weston kiosk renders it
    # badly. The NixOS module only offers kwin/weston enums, so the command
    # is overridden directly (settings wins over module defaults). The
    # absolute path keeps the sddm service free of PATH assumptions.
    settings.Wayland.CompositorCommand = "${inputs.hyprland.packages.${pkgs.system}.hyprland}/bin/start-hyprland -- --config /etc/sddm-greeter/hyprland.lua";

    # No autologin: LUKS auto-unlocks via TPM2 at boot (hosts/sakura), so the
    # single SDDM password is the machine's only prompt — and it unlocks the
    # keyring through the PAM hook above. With autologin the keyring could
    # never be unlocked (no password ever reaches PAM) and prompted on use.
  };

  # Upstream's minimal Hyprland config for the greeter (default/sddm/
  # hyprland.lua), with kebun's input delta appended (sddmGreeterHyprland):
  # disables the logo/splash and animations; hl.* is Hyprland's native Lua
  # API, so the file is standalone.
  environment.etc."sddm-greeter/hyprland.lua".source = "${sddmGreeterHyprland}/hyprland.lua";

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

  # ─── Omarchy shell lock plugin PAM stack ───
  # The QuickShell lock screen probes /etc/pam.d/omarchy-lock-password and
  # refuses to lock without it ("missing-pam"). Fingerprint unlock
  # (omarchy-lock-fingerprint + fprintd) is deferred — see backlog §3.2.
  security.pam.services."omarchy-lock-password" = {};

  # ─── Desktop packages (system-level) ───
  environment.systemPackages = with pkgs; [
    # SDDM theme (must be in systemPackages for /run/current-system/sw/share/sddm/themes)
    sddmThemeOmarchy

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

    # Polkit (already enabled above, but ensure package is available)
    polkit

    # Audio controls
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
  ];

  # ─── Bluetooth ───
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ─── D-Bus ───
  services.dbus.enable = true;
}
