{ config, pkgs, ... }: {
  programs.helix = {
    enable = true;
    defaultEditor = false; # Neovim remains default editor

    settings = {
      theme = "rose_pine_dawn";
      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        auto-save = true;
        indent-guides.render = true;
        bufferline = "multiple";
        soft-wrap.enable = true;
        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
      };

      keys.normal = {
        space.space = "file_picker";
        space.w = ":w";
        space.q = ":q";
        space.f = "file_picker";
        space.b = "buffer_picker";
        "C-f" = ":fmt";  # format on Ctrl-f
      };
    };
  };
}
