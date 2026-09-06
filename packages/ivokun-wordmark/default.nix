# The IVOKUN wordmark, shared by the SDDM greeter (sddmThemeOmarchy) and the
# Plymouth boot splash — one derivation so both surfaces show the identical
# logo. Rendered at build time from the single-sourced palette: accent fill,
# JetBrainsMono Nerd Font (the greeter theme's family), transparent
# background, trimmed + bordered to approximate the upstream logo's inset.
{pkgs}: let
  palette = import ../../lib/palette.nix;
  font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
in
  pkgs.runCommand "ivokun-wordmark" {} ''
    mkdir -p $out
    ${pkgs.imagemagick}/bin/convert \
      -background none -fill '${palette.accent}' \
      -font ${font} -pointsize 96 label:'IVOKUN' -trim +repage \
      -bordercolor none -border 12 \
      $out/logo.png
  ''
