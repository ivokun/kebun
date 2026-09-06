{pkgs}: let
  # Colors stay single-sourced in lib/palette.nix. Hex → 0-255 decimal
  # components for ImageMagick rgba()/rgb() strings (expanded by bash), and
  # hex → 0-1 float literals for Plymouth's Window.SetBackground*Color
  # (computed in Nix — the script heredoc is quoted, so bash arithmetic
  # would be pasted verbatim into Plymouth's scripting language).
  palette = import ../../lib/palette.nix;
  ivokunWordmark = pkgs.callPackage ../ivokun-wordmark {};

  fg = palette.foreground; # Dawn text
  bg = palette.background; # Dawn base
  ac = palette.accent; # Dawn foam

  hexDec = h: let
    d = builtins.replaceStrings ["#"] [""] h;
    ch = i: "$((16#${builtins.substring i 2 d}))";
  in "${ch 0},${ch 2},${ch 4}";

  hexToInt = s: let
    hexDigit = c:
      {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
      }
      .${
        c
      }
      or (throw "bad hex digit: ${c}");
  in
    # Horner fold: every digit shifts the accumulator — no per-digit recursion
    # (a naive `dec(head) * 16 + go(tail)` multiplies the LAST digit too:
    # #faf4ed parsed as (15+10)*16 = 400, i.e. background floats > 1).
    builtins.foldl' (acc: c: acc * 16 + hexDigit c) 0 (pkgs.lib.stringToCharacters s);

  hexFloats = h: let
    d = builtins.replaceStrings ["#"] [""] h;
    v = i: hexToInt (builtins.substring i 2 d);
  in "${toString (v 0 / 255.0)}, ${toString (v 2 / 255.0)}, ${toString (v 4 / 255.0)}";

  consoleBg = builtins.replaceStrings ["#"] ["0x"] bg;
  bgFloats = hexFloats bg;
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "plymouth-theme-kebun";
    version = "0.2.0";

    src = null;
    dontUnpack = true;

    nativeBuildInputs = [pkgs.imagemagick];

    installPhase = ''
        mkdir -p $out/share/plymouth/themes/kebun

        themeDir=$out/share/plymouth/themes/kebun

        # IVOKUN wordmark — the same derivation the SDDM greeter uses, so boot
        # and login show the identical logo.
        cp ${ivokunWordmark}/logo.png "$themeDir/logo.png"

        # Password entry field (280x48): faint Dawn-text wash + thin frame,
        # echoing the greeter's entry.png.
        convert -size 280x48 xc:none \
          -fill "rgba(${hexDec fg},0.07)" -draw 'roundrectangle 0,0 279,47 12,12' \
          -stroke "rgba(${hexDec fg},0.4)" -strokewidth 1.5 \
          -draw 'roundrectangle 0,0 279,47 12,12' \
          "$themeDir/entry.png"

        # Lock icon (40x48) in Dawn text: shackle arc, body over the shackle
        # legs, keyhole punched in the background color.
        convert -size 40x48 xc:none \
          -stroke "rgb(${hexDec fg})" -strokewidth 5 -fill none \
          -draw 'arc 11,7 29,33 180,360' \
          -stroke none -fill "rgb(${hexDec fg})" \
          -draw 'roundrectangle 5,21 35,45 5,5' \
          -fill "rgb(${hexDec bg})" \
          -draw 'circle 20,30 20,33' \
          -draw 'polygon 18,30 22,30 23,40 17,40' \
          "$themeDir/lock.png"

        # Bullet (14x14 dot) in Dawn text.
        convert -size 14x14 xc:none \
          -fill "rgb(${hexDec fg})" -draw 'circle 7,7 7,0' \
          "$themeDir/bullet.png"

        # Progress bar fill (300x4) in the accent color; track as a faint
        # Dawn-text wash.
        convert -size 300x4 xc:none \
          -fill "rgb(${hexDec ac})" -draw 'roundrectangle 0,0 300,4 2,2' \
          "$themeDir/progress_bar.png"
        convert -size 300x4 xc:none \
          -fill "rgba(${hexDec fg},0.15)" -draw 'roundrectangle 0,0 300,4 2,2' \
          "$themeDir/progress_box.png"

        # Theme descriptor. Absolute $out paths so the NOS Plymouth module can
        # rewrite them correctly for the initrd; relative or /share-only paths
        # break image loading.
        cat > "$themeDir/kebun.plymouth" <<EOF
      [Plymouth Theme]
      Name=Kebun
      Description=Kebun boot splash — Rose Pine Dawn light, IVOKUN wordmark
      ModuleName=script

      [script]
      ImageDir=$themeDir
      ScriptFile=$themeDir/kebun.script
      ConsoleLogBackgroundColor=${consoleBg}
      MonospaceFont=Cantarell 11
      Font=Cantarell 11
      EOF

        # Plymouth script — Plymouth's JavaScript-like scripting language.
        # Solid Dawn base background; the greeter's exact look.
        cat > "$themeDir/kebun.script" <<'SCRIPT'
      # Kebun Plymouth Theme
      # Colors: bg=#faf4ed (Dawn base) fg=#575279 accent=#56949f error=#b4637a

      Window.SetBackgroundTopColor(${bgFloats});
      Window.SetBackgroundBottomColor(${bgFloats});

      # --- Logo ---
      logo_image = Image("logo.png");
      logo_sprite = Sprite(logo_image);
      logo_sprite.SetZ(10);
      logo_sprite.SetX(Window.GetWidth() / 2 - logo_image.GetWidth() / 2);
      logo_sprite.SetY(Window.GetHeight() / 2 - logo_image.GetHeight() / 2 - 60);

      # --- Progress bar (bottom of screen) ---
      progress_box_image = Image("progress_box.png");
      progress_box_sprite = Sprite(progress_box_image);
      progress_box_sprite.SetZ(10);
      progress_box_sprite.SetX(Window.GetWidth() / 2 - progress_box_image.GetWidth() / 2);
      progress_box_sprite.SetY(Window.GetHeight() - progress_box_image.GetHeight() - 40);
      progress_box_sprite.SetOpacity(0);

      progress_bar_image = Image("progress_bar.png");
      progress_bar_sprite = Sprite();
      progress_bar_sprite.SetZ(11);
      progress_bar_sprite.SetX(Window.GetWidth() / 2 - progress_bar_image.GetWidth() / 2);
      progress_bar_sprite.SetY(Window.GetHeight() - progress_bar_image.GetHeight() - 40);
      progress_bar_sprite.SetOpacity(0);

      # --- Password dialog assets ---
      entry_image = Image("entry.png");
      entry_sprite = Sprite(entry_image);
      entry_sprite.SetZ(10);
      entry_sprite.SetX(Window.GetWidth() / 2 - entry_image.GetWidth() / 2);
      entry_sprite.SetY(Window.GetHeight() / 2 + 60);
      entry_sprite.SetOpacity(0);

      lock_image = Image("lock.png");
      lock_sprite = Sprite(lock_image);
      lock_sprite.SetZ(12);
      lock_sprite.SetX(Window.GetWidth() / 2 - entry_image.GetWidth() / 2 - lock_image.GetWidth() - 12);
      lock_sprite.SetY(Window.GetHeight() / 2 + 60 + entry_image.GetHeight() / 2 - lock_image.GetHeight() / 2);
      lock_sprite.SetOpacity(0);

      # Bullet sprites (pre-create, toggle opacity)
      bullet_image = Image("bullet.png");
      bullet_sprites = [];
      for (i = 0; i < 21; i++) {
        bullet_sprites[i] = Sprite(bullet_image);
        bullet_sprites[i].SetZ(12);
        bullet_sprites[i].SetX(Window.GetWidth() / 2 - entry_image.GetWidth() / 2 + 20 + i * 16);
        bullet_sprites[i].SetY(Window.GetHeight() / 2 + 60 + entry_image.GetHeight() / 2 - bullet_image.GetHeight() / 2);
        bullet_sprites[i].SetOpacity(0);
      }

      # --- Callbacks ---

      fun refresh_callback () {
        # Nothing to animate continuously
      }

      fun progress_callback (duration, progress) {
        if (progress > 0) {
          width = Math.Int(progress_bar_image.GetWidth() * progress);
          if (width < 1) width = 1;
          scaled = progress_bar_image.Scale(width, progress_bar_image.GetHeight());
          progress_bar_sprite.SetImage(scaled);
          progress_bar_sprite.SetOpacity(1);
          progress_box_sprite.SetOpacity(1);
        }
      }

      fun display_password_callback (prompt, bullets) {
        progress_box_sprite.SetOpacity(0);
        progress_bar_sprite.SetOpacity(0);

        entry_sprite.SetOpacity(1);
        lock_sprite.SetOpacity(1);

        max_bullets = 21;
        bullets_to_show = bullets;
        if (bullets_to_show > max_bullets) bullets_to_show = max_bullets;

        for (i = 0; i < bullets_to_show; i++) {
          bullet_sprites[i].SetOpacity(1);
        }
        for (i = bullets_to_show; i < max_bullets; i++) {
          bullet_sprites[i].SetOpacity(0);
        }
      }

      fun display_normal_callback () {
        entry_sprite.SetOpacity(0);
        lock_sprite.SetOpacity(0);
        for (i = 0; i < 21; i++) {
          bullet_sprites[i].SetOpacity(0);
        }

        progress_box_sprite.SetOpacity(1);
        progress_bar_sprite.SetOpacity(1);
      }

      Plymouth.SetRefreshFunction(refresh_callback);
      Plymouth.SetBootProgressFunction(progress_callback);
      Plymouth.SetDisplayPasswordFunction(display_password_callback);
      Plymouth.SetDisplayNormalFunction(display_normal_callback);
      SCRIPT
    '';

    meta = with pkgs.lib; {
      description = "Kebun Plymouth theme — Rose Pine Dawn light with IVOKUN wordmark";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
