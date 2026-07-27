{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "plymouth-theme-kebun";
  version = "0.1.0";

  src = null;
  dontUnpack = true;

  nativeBuildInputs = [pkgs.imagemagick];

  installPhase = ''
        mkdir -p $out/share/plymouth/themes/kebun

        themeDir=$out/share/plymouth/themes/kebun

        # Copy static logo and resize to 200x200
        convert ${./logo.png} -resize 200x200 "$themeDir/logo.png"

        # Generate subtle 1920x1080 background with a darker cyan vignette
        convert -size 1920x1080 xc:none \
          -fill '#0ea5e9' -draw 'rectangle 0,0 1920,1080' \
          -fill 'rgba(2,132,199,0.4)' -draw 'roundrectangle 120,120 1800,960 64,64' \
          "$themeDir/background.png"

        # Generate bullet (14x14 yellow circle)
        convert -size 14x14 xc:none \
          -fill '#facc15' -draw 'circle 7,7 7,0' \
          "$themeDir/bullet.png"

        # Generate entry field (280x48 semi-transparent dark rounded rect)
        convert -size 280x48 xc:none \
          -fill 'rgba(0,0,0,0.5)' -draw 'roundrectangle 0,0 280,48 12,12' \
          "$themeDir/entry.png"

        # Generate lock icon (40x48 yellow padlock: arch shackle + body + keyhole).
        # Draw the shackle arc first, then the body on top so it covers the shackle
        # legs, then cut a keyhole in the darker cyan.
        convert -size 40x48 xc:none \
          -stroke '#facc15' -strokewidth 5 -fill none \
          -draw 'arc 11,7 29,33 180,360' \
          -stroke none -fill '#facc15' \
          -draw 'roundrectangle 5,21 35,45 5,5' \
          -fill '#0284c7' \
          -draw 'circle 20,30 20,33' \
          -draw 'polygon 18,30 22,30 23,40 17,40' \
          "$themeDir/lock.png"

        # Generate progress bar fill (300x4 yellow rounded)
        convert -size 300x4 xc:none \
          -fill '#facc15' -draw 'roundrectangle 0,0 300,4 2,2' \
          "$themeDir/progress_bar.png"

        # Generate progress bar track (300x4 semi-transparent dark rounded)
        convert -size 300x4 xc:none \
          -fill 'rgba(0,0,0,0.3)' -draw 'roundrectangle 0,0 300,4 2,2' \
          "$themeDir/progress_box.png"

        # Theme descriptor
        # Use absolute $out paths so the NixOS Plymouth module can rewrite them
        # correctly for the initrd; relative or /share-only paths break image loading.
        cat > "$themeDir/kebun.plymouth" <<EOF
    [Plymouth Theme]
    Name=Kebun
    Description=Kebun boot splash with ivokun branding
    ModuleName=script

    [script]
    ImageDir=$themeDir
    ScriptFile=$themeDir/kebun.script
    ConsoleLogBackgroundColor=0x0ea5e9
    MonospaceFont=Cantarell 11
    Font=Cantarell 11
    EOF

        # Plymouth script — uses Plymouth's JavaScript-like scripting language
        # Key API: Image("file"), Sprite(image), Sprite() for empty sprites
        cat > "$themeDir/kebun.script" <<'SCRIPT'
    # Kebun Plymouth Theme
    # Colors: bg=#0ea5e9 fg=#facc15 error=#f43f5e

    Window.SetBackgroundTopColor(0.055, 0.647, 0.914);
    Window.SetBackgroundBottomColor(0.055, 0.647, 0.914);

    # --- Background image ---
    background_image = Image("background.png");
    background_sprite = Sprite(background_image);
    background_sprite.SetX(0);
    background_sprite.SetY(0);
    background_sprite.SetZ(0);
    background_sprite.SetOpacity(1);

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
    description = "Kebun Plymouth theme with ivokun branding";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
