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
        color = "blue";
        padding = {
          right = 2;
        };
      };

      display = {
        color = {
          keys = "magenta";
          title = "cyan";
        };
        separator = "  ";
      };

      modules = [
        {
          type = "title";
          color = {
            user = "cyan";
            host = "blue";
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
          keyColor = "green";
        }
        {
          type = "kernel";
          key = "  Kernel";
          keyColor = "green";
        }
        {
          type = "uptime";
          key = "  Uptime";
          keyColor = "green";
        }
        {
          type = "packages";
          key = "  Packages";
          keyColor = "green";
        }
        {
          type = "shell";
          key = "  Shell";
          keyColor = "green";
        }
        {
          type = "de";
          key = "  DE";
          keyColor = "green";
        }
        {
          type = "wm";
          key = "  WM";
          keyColor = "green";
        }
        {
          type = "theme";
          key = "  Theme";
          keyColor = "green";
        }
        {
          type = "icons";
          key = "  Icons";
          keyColor = "green";
        }
        {
          type = "terminal";
          key = "  Terminal";
          keyColor = "green";
        }
        {
          type = "font";
          key = "  Font";
          keyColor = "green";
        }
        "break"
        {
          type = "custom";
          format = "├─────────── [1mHardware Information[0m ───────────┤";
        }
        {
          type = "host";
          key = "  Host";
          keyColor = "blue";
        }
        {
          type = "cpu";
          key = "  CPU";
          keyColor = "blue";
        }
        {
          type = "gpu";
          key = "  GPU";
          keyColor = "blue";
        }
        {
          type = "memory";
          key = "  Memory";
          keyColor = "blue";
        }
        {
          type = "swap";
          key = "  Swap";
          keyColor = "blue";
        }
        {
          type = "disk";
          key = "  Disk";
          keyColor = "blue";
          folders = "/";
        }
        {
          type = "battery";
          key = "  Battery";
          keyColor = "blue";
        }
        {
          type = "display";
          key = "  Display";
          keyColor = "blue";
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
