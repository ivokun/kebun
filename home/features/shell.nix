{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  programs.zsh = {
    enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "refined";
      plugins = [
        "git"
        "you-should-use"
      ];
    };

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      vim = "nvim";
      vi = "nvim";
      ls = "eza -lh --group-directories-first --icons=auto";
      lsa = "ls -a";
      lt = "eza --tree --level=2 --long --icons --git";
      lta = "lt -a";
      ff = "fzf --preview 'bat --style=numbers --color=always {}'";
      decompress = "tar -xzf";
    };

    envExtra = ''
      export LANG=en_US.UTF-8
      export LC_CTYPE=en_US.UTF-8
      export LC_ALL="en_US.UTF-8"
      export TERM="xterm-256color"
      export TERMINAL=alacritty
      export EDITOR="nvim"
      export SUDO_EDITOR="$EDITOR"
    '';

    initExtra = ''
      # ─── Custom Functions ───
      # Zoxide wrapper with pwd display
      zd() {
        if [ $# -eq 0 ]; then
          local dir
          dir=$(zoxide query --interactive) && cd "$dir"
        else
          zoxide "$@"
        fi
        echo "📍 $(pwd)"
      }

      # xdg-open wrapper
      open() {
        xdg-open "$@" &> /dev/null &
      }

      # Compress files
      compress() {
        tar -czf "$1.tar.gz" "$@"
      }

      # Write ISO to SD card
      iso2sd() {
        local iso="$1"
        local device="$2"
        if [ -z "$iso" ] || [ -z "$device" ]; then
          echo "Usage: iso2sd <iso-file> <device>"
          return 1
        fi
        sudo dd if="$iso" of="$device" bs=4M status=progress conv=fsync
      }

      # Create webapp desktop entry
      web2app() {
        local name="$1"
        local url="$2"
        local icon="$3"
        if [ -z "$name" ] || [ -z "$url" ]; then
          echo "Usage: web2app <name> <url> [icon]"
          return 1
        fi
        mkdir -p ~/.local/share/applications
        cat > ~/.local/share/applications/"$name".desktop << EOF
      [Desktop Entry]
      Name=$name
      Exec=brave --app="$url"
      Type=Application
      Icon=$icon
      Categories=Network;WebBrowser;
      EOF
        echo "Created ~/.local/share/applications/$name.desktop"
      }

      # Remove webapp desktop entry
      web2app-remove() {
        local name="$1"
        if [ -z "$name" ]; then
          echo "Usage: web2app-remove <name>"
          return 1
        fi
        rm -f ~/.local/share/applications/"$name".desktop
        echo "Removed ~/.local/share/applications/$name.desktop"
      }

      # Restart fcitx5 for XCompose changes
      refresh-xcompose() {
        fcitx5 -r &
      }

      # Override cd to show pwd
      cd() {
        builtin cd "$@" && echo "📍 $(pwd)"
      }

      # Activate mise
      if command -v mise &> /dev/null; then
        eval "$(mise activate zsh)"
      fi
    '';
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = true;
      command_timeout = 200;
      format = "[$directory$git_branch$git_status]($style)$character";

      character = {
        error_symbol = "[✗](bold cyan)";
        success_symbol = "[❯](bold cyan)";
      };

      directory = {
        truncation_length = 2;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
      };

      git_branch = {
        format = "[$branch]($style) ";
        style = "italic cyan";
      };

      git_status = {
        format = "[$all_status]($style)";
        style = "cyan";
        ahead = "⇡\${count} ";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count} ";
        behind = "⇣\${count} ";
        conflicted = " ";
        up_to_date = " ";
        untracked = "? ";
        modified = " ";
        stashed = "";
        staged = "";
        renamed = "";
        deleted = "";
      };
    };
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = true;
      sync_address = "https://nuc01.tetra-banded.ts.net/atuin/";
      enter_accept = true;
      search_mode = "fuzzy";
      records = true;
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
  };

  programs.bat = {
    enable = true;
  };

  programs.fd = {
    enable = true;
  };

  programs.ripgrep = {
    enable = true;
  };

  programs.nix-index = {
    enable = true;
  };

  # ─── Auto-start Hyprland on TTY login ───
  home.file.".zprofile".text = ''
    if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
      exec uwsm start hyprland-uwsm.desktop
    fi
  '';

  # ─── XCompose custom sequences ───
  home.file.".XCompose".text = ''
    # Custom compose sequences
    include "%L"

    # Name
    <Multi_key> <space> <n> : "Salahuddin Muhammad Iqbal"

    # Email
    <Multi_key> <space> <e> : "salahuddin.mi@gmail.com"
  '';

  # ─── Oh-my-zsh custom plugins ───
  home.file.".oh-my-zsh/custom/plugins/you-should-use".source = "${pkgs.zsh-you-should-use}/share/zsh/plugins/you-should-use";

  # ─── mise config ───
  home.file.".config/mise/config.toml".text = ''
    [tools]
    aws = "latest"
    bun = "latest"
    go = "latest"
    node = "latest"
    pnpm = "9.5.0"
    uv = "latest"

    [settings]
    idiomatic_version_file_enable_tools = ["python"]
  '';
}
