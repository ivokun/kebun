# Single source of truth for the Rose Pine Dawn palette (ADR-0007 Stage 5).
#
# Keys follow upstream's colors.toml schema (vendored at packages/omarchy:
# themes/rose-pine/colors.toml — which IS Dawn, mode = "light"), plus kebun's
# semantic aliases and per-app derived forms. Retheme = edit this file +
# rebuild; the omarchy shell picks the new theme up on its next restart
# (theme files are read at startup, watchChanges: false).
#
# Pure builtins only: importable from home modules and packages/scripts with
# a bare `import ../../lib/palette.nix` — no lib, no pkgs.
# Canonical spelling is hexes WITH the leading '#'; use `strip` where a
# hashless form is needed instead of re-declaring one.
rec {
  # ── upstream colors.toml schema (25 keys) ────────────────────────────────
  mode = "light";

  accent = "#56949f"; # Dawn foam
  selection = "#dfdad9"; # Dawn highlightMed
  muted = "#cecacd"; # upstream repurposes Dawn highlightHigh here

  background = "#faf4ed"; # Dawn base
  dark_background = "#ede7e1"; # Dawn surface
  darker_background = "#e1dbd5";
  lighter_background = "#f2e9e1"; # Dawn overlay

  foreground = "#575279"; # Dawn text
  dark_foreground = "#9893a5"; # Dawn muted text
  light_foreground = "#6e6a86";
  bright_foreground = "#575279";

  red = "#b4637a"; # love
  yellow = "#ea9d34"; # gold
  orange = "#cf8057";
  green = "#286983"; # pine
  cyan = "#d7827e"; # rose
  blue = "#56949f"; # foam
  magenta = "#907aa9"; # iris
  brown = "#67402b";

  bright_red = red;
  bright_yellow = yellow;
  bright_green = green;
  bright_cyan = cyan;
  bright_blue = blue;
  bright_magenta = magenta;

  # ── Dawn semantic names (kebun's usage vocabulary) ───────────────────────
  base = background;
  text = foreground;
  overlay = lighter_background;
  surface = dark_background;
  love = red;
  gold = yellow;
  rose = cyan;
  pine = green;
  foam = blue;
  iris = magenta;
  cursor = muted; # kebun's cursor color everywhere
  highlightMed = selection;
  highlightHigh = muted;
  mutedText = dark_foreground; # canonical Dawn "muted" text
  subtle = "#797593"; # Dawn subtle — kebun extension, not in the upstream 25

  # ── helpers ──────────────────────────────────────────────────────────────
  # Drop the leading '#': "${p.strip p.accent}" → "56949f" (rgb(…) forms).
  strip = s: builtins.replaceStrings ["#"] [""] s;

  # ── ANSI 16 (official Dawn terminal mapping) ─────────────────────────────
  ansi = [
    overlay
    love
    pine
    gold
    foam
    iris
    rose
    text
    mutedText
    love
    pine
    gold
    foam
    iris
    rose
    text
  ];

  # "0=#f2e9e1" … for ghostty's palette = space-joined list.
  ghosttyPalette = builtins.genList (i: "${toString i}=${builtins.elemAt ansi i}") 16;

  # "color0=#f2e9e1" … for kitty's colorN lines.
  kittyPalette = builtins.genList (i: "color${toString i}=${builtins.elemAt ansi i}") 16;

  # Decimal RGB triple for hyprland's misc fallback.
  backgroundRgb = "250,244,237";

  # ── colors.toml text (upstream byte layout) ──────────────────────────────
  # Consumed by packages/omarchy/theme.nix's build-time rendering; matches
  # the vendored themes/rose-pine/colors.toml.
  colorsToml =
    builtins.concatStringsSep "\n" [
      ''mode = "${mode}"''
      ""
      ''accent = "${accent}"''
      ''selection = "${selection}"''
      ''muted = "${muted}"''
      ""
      ''background = "${background}"''
      ''dark_background = "${dark_background}"''
      ''darker_background = "${darker_background}"''
      ''lighter_background = "${lighter_background}"''
      ""
      ''foreground = "${foreground}"''
      ''dark_foreground = "${dark_foreground}"''
      ''light_foreground = "${light_foreground}"''
      ''bright_foreground = "${bright_foreground}"''
      ""
      ''red = "${red}"''
      ''yellow = "${yellow}"''
      ''orange = "${orange}"''
      ''green = "${green}"''
      ''cyan = "${cyan}"''
      ''blue = "${blue}"''
      ''magenta = "${magenta}"''
      ''brown = "${brown}"''
      ""
      ''bright_red = "${bright_red}"''
      ''bright_yellow = "${bright_yellow}"''
      ''bright_green = "${bright_green}"''
      ''bright_cyan = "${bright_cyan}"''
      ''bright_blue = "${bright_blue}"''
      ''bright_magenta = "${bright_magenta}"''
    ]
    + "\n";
}
