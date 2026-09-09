# Omarchy v4 shell environment — ADR-0007 Stage 2, wired in at Stage 4.
#
# Ships the vendored QuickShell shell tree + IPC wrappers alongside
# quickshell. Since the Stage 4 stack swap, the shell is started by the
# compositor's autostart (uwsm-wrapped `omarchy-launch-shell`) and has
# replaced the v3 stack (waybar/walker/…).
{
  config,
  lib,
  pkgs,
  inputs,
  username,
  system,
  ...
}: let
  omarchy = import ../../packages/omarchy {
    inherit pkgs;
    hyprland = inputs.hyprland.packages.${system}.hyprland;
  };
  theme = import ../../packages/omarchy/theme.nix {inherit pkgs omarchy;};
in {
  home.packages = [
    omarchy
    pkgs.quickshell
    pkgs.inotify-tools
    # AppLibrary.qml launches desktop entries via `uwsm app -- gtk-launch …`,
    # resolving through the user-manager PATH. gtk-launch ships in gtk3's bin
    # (already in the closure as a library dependency) but NixOS never exposes
    # it; adding the package puts it on /etc/profiles/per-user PATH.
    pkgs.gtk3
  ];

  # The OMARCHY_PATH contract: shell QML, the wrappers, and (Stage 3) the
  # Hyprland Lua layer all read it. home.sessionVariables lands in both the
  # shell profile and the systemd user environment (environment.d).
  home.sessionVariables.OMARCHY_PATH = "${omarchy}";

  # Screenshot editor for omarchy-capture-screenshot's click-to-edit toast.
  # Upstream defaults to tensaku-edit (unpackaged in nixpkgs); the override
  # must be a single-word executable — notification --exec argv is never
  # re-parsed, so "swappy -f" would not word-split.
  home.sessionVariables.OMARCHY_SCREENSHOT_EDITOR = "screenshot-edit";

  # Stage 5: materialize the staged theme the shell reads at startup (Color.qml
  # reads exactly these two files, watchChanges: false). Both are rendered at
  # build time by the vendored upstream template engine — rebuild to retheme,
  # then restart the shell (omarchy-restart-shell) or relogin. HM deliberately
  # owns this generated state because multi-theme switching is out of scope
  # (ADR-0007 Stage 5): if omarchy-theme-set is ever run manually, HM restores
  # these files on the next switch (pre-existing copies get the hm-backup
  # suffix).
  home.file.".local/state/omarchy/current/theme/colors.toml".source = "${theme}/colors.toml";
  home.file.".local/state/omarchy/current/theme/shell.toml".source = "${theme}/shell.toml";

  # The shell's icon font: the bar menu button renders U+E900 from the
  # "omarchy" family (plugins/menu/BarWidget.qml). Upstream installs it as a
  # system font; HM stages it into the user font dir so fontconfig resolves
  # the family. Sourced from the pinned env so the font moves with the
  # vendored tree, like the theme files above.
  home.file.".local/share/fonts/omarchy/omarchy.ttf".source = "${omarchy}/default/fonts/omarchy/omarchy.ttf";

  # xdg-terminal-exec resolves the terminal for
  # omarchy-launch-floating-terminal-with-presentation, which backs most
  # terminal-based menu actions. Upstream relies on Arch's desktop entries;
  # kebun declares the default per the Default Terminal Execution
  # Specification instead. Alacritty matches TERMINAL in envs.lua.
  xdg.terminal-exec = {
    enable = true;
    settings = {
      default = ["Alacritty.desktop"];
      Hyprland = ["Alacritty.desktop"];
    };
  };

  # User menu override (the shell merges it over
  # $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc field-by-field by id).
  # Hides items whose actions assume Arch — pacman/AUR, upstream's runtime
  # theme/background/font switching (out of scope per ADR-0007: the theme is
  # single-sourced at build time), config "refresh" scripts that would clobber
  # HM-managed files, the factory reset, limine direct boot (sakura uses
  # systemd-boot), Arch-flavored security flows, NetworkManager DNS (kebun is
  # iwd per ADR-0002), and mise dev-envs (no mise on kebun — NixOS handles
  # toolchains). Overriding only `when` keeps the upstream icon/label; the
  # items return if kebun ever ports real equivalents.
  home.file.".config/omarchy/extensions/omarchy-menu.jsonc".text = builtins.toJSON (
    lib.genAttrs [
      # Theme machinery (build-time single-sourced instead).
      "style.theme"
      "style.background"
      "style.unlock"
      "style.font"
      # Pacman/AUR packaging.
      "install.package"
      "install.aur"
      "install.tui"
      "install.style"
      "install.development"
      "install.gaming.retro-launcher"
      "install.windows"
      "remove.package"
      "remove.tui"
      "remove.theme"
      "remove.development"
      # Upstream update machinery.
      "update.omarchy"
      "update.channel"
      "update.config"
      "update.themes"
      # Arch-only setup flows.
      "setup.reset"
      "setup.direct-boot"
      "setup.security"
      "setup.network.dns"
      # No herdr on kebun.
      "learn.herdr-keybindings"
    ] (_: {when = "false";})
  );
}
