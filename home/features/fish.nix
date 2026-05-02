{
  pkgs,
  lib,
  config,
  ...
}: {
  programs.fish = {
    enable = true;
    preferAbbrs = true;
    generateCompletions = true;

    shellInit = ''
      set -gx LANG en_US.UTF-8
      set -gx LC_CTYPE en_US.UTF-8
      set -gx LC_ALL en_US.UTF-8
      set -gx TERM xterm-256color
      set -gx TERMINAL alacritty
      set -gx EDITOR nvim
      set -gx SUDO_EDITOR $EDITOR
    '';

    loginShellInit = ''
      if test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = "1"
        exec uwsm start hyprland-uwsm.desktop
      end
    '';

    interactiveShellInit = ''
      mise activate fish | source
      set -g fish_greeting
    '';

    shellAbbrs = {
      vim = "nvim";
      vi = "nvim";
      ls = "eza -lh --group-directories-first --icons=auto";
      lsa = "eza -lha --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --long --icons --git";
      lta = "eza --tree --level=2 --long --icons --git -a";
      ff = "fzf --preview 'bat --style=numbers --color=always {}'";
      decompress = "tar -xzf";
      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit -v";
      gcmsg = "git commit -m";
      gd = "git diff";
      gds = "git diff --staged";
      gco = "git checkout";
      gcb = "git checkout -b";
      gp = "git push";
      gpll = "git pull";
      gst = "git status";
      glog = "git log --oneline --decorate --graph";
      gw = "git switch";
    };

    functions = {
      zd = ''
        if test (count $argv) -eq 0
          set -l dir (zoxide query --interactive)
          and cd $dir
        else
          zoxide $argv
        end
        echo "📍 $PWD"
      '';
      open = ''
        xdg-open $argv &> /dev/null &
      '';
      compress = ''
        tar -czf $argv[1].tar.gz $argv[2..]
      '';
      iso2sd = ''
        if test (count $argv) -ne 2
          echo "Usage: iso2sd <iso> <device>"
          return 1
        end
        sudo dd if=$argv[1] of=$argv[2] bs=4M status=progress conv=fsync
      '';
      web2app = ''
        if test (count $argv) -lt 2
          echo "Usage: web2app <name> <url> [icon]"
          return 1
        end
        set name $argv[1]
        set url $argv[2]
        set icon $argv[3]
        set desktop_dir $HOME/.local/share/applications
        mkdir -p $desktop_dir
        set desktop_file $desktop_dir/$name.desktop
        echo "[Desktop Entry]" > $desktop_file
        echo "Name=$name" >> $desktop_file
        echo "Exec=brave --app=$url" >> $desktop_file
        echo "Type=Application" >> $desktop_file
        echo "Categories=Network;WebBrowser;" >> $desktop_file
        if test -n "$icon"
          echo "Icon=$icon" >> $desktop_file
        end
        echo "Created $desktop_file"
      '';
      web2app-remove = ''
        set name $argv[1]
        set desktop_file $HOME/.local/share/applications/$name.desktop
        if test -f $desktop_file
          rm $desktop_file
          echo "Removed $desktop_file"
        else
          echo "No such webapp: $name"
          return 1
        end
      '';
      refresh-xcompose = ''
        fcitx5 -r & disown
      '';
    };

    plugins = [
      {
        name = "fish-abbreviation-tips";
        src = pkgs.fetchFromGitHub {
          owner = "gazorby";
          repo = "fish-abbreviation-tips";
          rev = "v0.7.0";
          sha256 = "05b5qp7yly7mwsqykjlb79gl24bs6mbqzaj5b3xfn3v2b7apqnqp";
        };
      }
    ];
  };
}
