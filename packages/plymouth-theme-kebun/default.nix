{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "plymouth-theme-kebun";
  version = "0.1.0";

  src = null;
  dontUnpack = true;

  nativeBuildInputs = [pkgs.imagemagick];

  installPhase = ''
        mkdir -p $out/share/plymouth/themes/kebun

        # Copy static logo and resize to 200x200
        convert ${./logo.png} -resize 200x200 $out/share/plymouth/themes/kebun/logo.png

        # Generate bullet (14x14 yellow circle)
        convert -size 14x14 xc:none \
          -fill '#facc15' -draw 'circle 7,7 7,0' \
          $out/share/plymouth/themes/kebun/bullet.png

        # Generate entry field (280x48 semi-transparent dark rounded rect)
        convert -size 280x48 xc:none \
          -fill 'rgba(0,0,0,0.5)' -draw 'roundrectangle 0,0 280,48 12,12' \
          $out/share/plymouth/themes/kebun/entry.png

        # Generate lock icon (42x48 yellow)
        convert -size 42x48 xc:none \
          -fill '#facc15' -draw 'roundrectangle 6,20 36,44 3,3' \
          -stroke '#facc15' -strokewidth 4 -fill none \
          -draw 'roundrectangle 11,4 31,20 8,8' \
          $out/share/plymouth/themes/kebun/lock.png

        # Generate progress bar fill (300x4 yellow rounded)
        convert -size 300x4 xc:none \
          -fill '#facc15' -draw 'roundrectangle 0,0 300,4 2,2' \
          $out/share/plymouth/themes/kebun/progress_bar.png

        # Generate progress bar track (300x4 semi-transparent dark rounded)
        convert -size 300x4 xc:none \
          -fill 'rgba(0,0,0,0.3)' -draw 'roundrectangle 0,0 300,4 2,2' \
          $out/share/plymouth/themes/kebun/progress_box.png

        # Theme descriptor
        cat > $out/share/plymouth/themes/kebun/kebun.plymouth <<EOF
    [Plymouth Theme]
    Name=Kebun
    Description=Kebun boot splash with ivokun branding
    ModuleName=script

    [script]
    ImageDir=/share/plymouth/themes/kebun
    ScriptFile=/share/plymouth/themes/kebun/kebun.script
    ConsoleLogBackgroundColor=0x0ea5e9
    MonospaceFont=Cantarell 11
    Font=Cantarell 11
    EOF

        # Plymouth script — uses Plymouth's JavaScript-like scripting language
        # Key API: Image("file"), Sprite(image), Sprite() for empty sprites
        cat > $out/share/plymouth/themes/kebun/kebun.script <<'SCRIPT'
    # Kebun Plymouth Theme
    # Colors: bg=#0ea5e9 fg=#facc15 error=#f43f5e

    Window.SetBackgroundTopColor(0.055, 0.647, 0.914);
    Window.SetBackgroundBottomColor(0.055, 0.647, 0.914);

    # --- Logo ---
    logo_image = Image("logo.png");
    logo_sprite = Sprite(logo_image);
    logo_sprite.SetX(Window.GetWidth() / 2 - logo_image.GetWidth() / 2);
    logo_sprite.SetY(Window.GetHeight() / 2 - logo_image.GetHeight() / 2 - 60);

    # --- Progress bar ---
    progress_box_image = Image("progress_box.png");
    progress_box_sprite = Sprite(progress_box_image);
    progress_box_sprite.SetX(Window.GetWidth() / 2 - progress_box_image.GetWidth() / 2);
    progress_box_sprite.SetY(Window.GetHeight() / 2 + 80);
    progress_box_sprite.SetOpacity(0);

    progress_bar_image = Image("progress_bar.png");
    progress_bar_sprite = Sprite();
    progress_bar_sprite.SetX(Window.GetWidth() / 2 - progress_bar_image.GetWidth() / 2);
    progress_bar_sprite.SetY(Window.GetHeight() / 2 + 80);
    progress_bar_sprite.SetOpacity(0);

    # --- Password dialog assets ---
    entry_image = Image("entry.png");
    entry_sprite = Sprite(entry_image);
    entry_sprite.SetX(Window.GetWidth() / 2 - entry_image.GetWidth() / 2);
    entry_sprite.SetY(Window.GetHeight() / 2 + 60);
    entry_sprite.SetOpacity(0);

    lock_image = Image("lock.png");
    lock_sprite = Sprite(lock_image);
    lock_sprite.SetX(Window.GetWidth() / 2 - entry_image.GetWidth() / 2 - lock_image.GetWidth() - 12);
    lock_sprite.SetY(Window.GetHeight() / 2 + 60 + entry_image.GetHeight() / 2 - lock_image.GetHeight() / 2);
    lock_sprite.SetOpacity(0);

    # Bullet sprites (pre-create, toggle opacity)
    bullet_image = Image("bullet.png");
    bullet_sprites = [];
    for (i = 0; i < 21; i++) {
      bullet_sprites[i] = Sprite(bullet_image);
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
    description = "Kebun Plymouth theme with ivokun branding";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
