{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.fastfetch = {
    enable = true;

    settings = {
      logo = {
        source = "nixos";
        color = "#286983";
        padding = {
          right = 2;
        };
      };

      display = {
        color = {
          keys = "#907aa9";
          title = "#56949f";
        };
        separator = "  ";
      };

      modules = [
        {
          type = "title";
          color = {
            user = "#56949f";
            host = "#907aa9";
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
          keyColor = "#56949f";
        }
        {
          type = "kernel";
          key = "  Kernel";
          keyColor = "#56949f";
        }
        {
          type = "uptime";
          key = "  Uptime";
          keyColor = "#56949f";
        }
        {
          type = "packages";
          key = "  Packages";
          keyColor = "#56949f";
        }
        {
          type = "shell";
          key = "  Shell";
          keyColor = "#56949f";
        }
        {
          type = "de";
          key = "  DE";
          keyColor = "#56949f";
        }
        {
          type = "wm";
          key = "  WM";
          keyColor = "#56949f";
        }
        {
          type = "theme";
          key = "  Theme";
          keyColor = "#56949f";
        }
        {
          type = "icons";
          key = "  Icons";
          keyColor = "#56949f";
        }
        {
          type = "terminal";
          key = "  Terminal";
          keyColor = "#56949f";
        }
        {
          type = "font";
          key = "  Font";
          keyColor = "#56949f";
        }
        "break"
        {
          type = "custom";
          format = "├─────────── [1mHardware Information[0m ───────────┤";
        }
        {
          type = "host";
          key = "  Host";
          keyColor = "#286983";
        }
        {
          type = "cpu";
          key = "  CPU";
          keyColor = "#286983";
        }
        {
          type = "gpu";
          key = "  GPU";
          keyColor = "#286983";
        }
        {
          type = "memory";
          key = "  Memory";
          keyColor = "#286983";
        }
        {
          type = "swap";
          key = "  Swap";
          keyColor = "#286983";
        }
        {
          type = "disk";
          key = "  Disk";
          keyColor = "#286983";
          folders = "/";
        }
        {
          type = "battery";
          key = "  Battery";
          keyColor = "#286983";
        }
        {
          type = "display";
          key = "  Display";
          keyColor = "#286983";
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
