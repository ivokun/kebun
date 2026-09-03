{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;
in {
  programs.fastfetch = {
    enable = true;

    settings = {
      logo = {
        source = "nixos";
        padding = {
          right = 2;
        };
      };

      display = {
        color = {
          keys = palette.iris;
          title = palette.foam;
        };
        separator = "  ";
      };

      modules = [
        {
          type = "title";
          color = {
            user = palette.foam;
            host = palette.iris;
          };
        }
        "break"
        {
          type = "custom";
          format = "┌─────────── [1mSystem Information[0m ───────────┐";
        }
        {
          type = "os";
          key = "  OS";
          keyColor = palette.foam;
        }
        {
          type = "kernel";
          key = "  Kernel";
          keyColor = palette.foam;
        }
        {
          type = "uptime";
          key = "  Uptime";
          keyColor = palette.foam;
        }
        {
          type = "packages";
          key = "  Packages";
          keyColor = palette.foam;
        }
        {
          type = "shell";
          key = "  Shell";
          keyColor = palette.foam;
        }
        {
          type = "de";
          key = "  DE";
          keyColor = palette.foam;
        }
        {
          type = "wm";
          key = "  WM";
          keyColor = palette.foam;
        }
        {
          type = "theme";
          key = "  Theme";
          keyColor = palette.foam;
        }
        {
          type = "icons";
          key = "  Icons";
          keyColor = palette.foam;
        }
        {
          type = "terminal";
          key = "  Terminal";
          keyColor = palette.foam;
        }
        {
          type = "font";
          key = "  Font";
          keyColor = palette.foam;
        }
        "break"
        {
          type = "custom";
          format = "├─────────── [1mHardware Information[0m ───────────┤";
        }
        {
          type = "host";
          key = "  Host";
          keyColor = palette.pine;
        }
        {
          type = "cpu";
          key = "  CPU";
          keyColor = palette.pine;
        }
        {
          type = "gpu";
          key = "  GPU";
          keyColor = palette.pine;
        }
        {
          type = "memory";
          key = "  Memory";
          keyColor = palette.pine;
        }
        {
          type = "swap";
          key = "  Swap";
          keyColor = palette.pine;
        }
        {
          type = "disk";
          key = "  Disk";
          keyColor = palette.pine;
          folders = "/";
        }
        {
          type = "battery";
          key = "  Battery";
          keyColor = palette.pine;
        }
        {
          type = "display";
          key = "  Display";
          keyColor = palette.pine;
        }
        "break"
        {
          type = "custom";
          format = "└────────────────────────────────────────────┘";
        }
        "break"
        {
          type = "colors";
          symbol = "circle";
        }
      ];
    };
  };
}
