{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # ─── Neovim ───
  # LazyVim is best managed outside home-manager since it manages its own plugins.
  # We source the full LazyVim starter + custom configs from the repo.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
  };

  home.file.".config/nvim" = {
    source = ../nvim;
    recursive = true;
  };

  # ─── Git ───
  programs.git = {
    enable = true;
    userName = "Salahuddin Muhammad Iqbal";
    userEmail = "salahuddin.mi@gmail.com";

    aliases = {
      co = "checkout";
      br = "branch";
      ci = "commit";
      st = "status";
      lg = "log --oneline --graph --decorate --all";
      last = "log -1 HEAD";
      unstage = "reset HEAD --";
      amend = "commit --amend";
    };

    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rerere.enabled = true;
      diff.colorMoved = "default";
    };

    signing = {
      key = null;
      signByDefault = false;
    };
  };

  # ─── Lazygit ───
  programs.lazygit = {
    enable = true;
  };

  # ─── tmux ───
  programs.tmux = {
    enable = true;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents on
          set -g @resurrect-strategy-nvim session
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore on
          set -g @continuum-save-interval 10
        '';
      }
      {
        plugin = rose-pine;
        extraConfig = ''
          set -g @rose_pine_variant 'dawn'
          set -g @rose_pine_date_time "%Y-%m-%d %H:%M"
          set -g @rose_pine_status_right_append_section " #{battery_percentage}"
        '';
      }
      yank
      battery
      vim-tmux-navigator
    ];

    extraConfig = ''
      # General Settings
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",*:RGB"
      set -g history-limit 50000
      set -g mouse on
      set -g status-position top
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -s escape-time 0
      set -g focus-events on
      set -g detach-on-destroy off
      setw -g aggressive-resize on
      set -g extended-keys on

      # Copy mode (Vi style) — yank plugin handles clipboard integration
      setw -g mode-keys vi

      # Prefix (C-a)
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix

      # Reload config
      bind q source-file ~/.config/tmux/tmux.conf \; display "Configuration reloaded"

      # Pane splitting
      bind v split-window -h -c "#{pane_current_path}"
      bind h split-window -v -c "#{pane_current_path}"
      bind x kill-pane
      bind c new-window -c "#{pane_current_path}"

      # Pane Navigation (Alt+Ctrl+Arrows)
      bind -n C-M-Left select-pane -L
      bind -n C-M-Right select-pane -R
      bind -n C-M-Up select-pane -U
      bind -n C-M-Down select-pane -D

      # Pane Resizing
      bind -n C-M-S-Left resize-pane -L 5
      bind -n C-M-S-Down resize-pane -D 5
      bind -n C-M-S-Up resize-pane -U 5
      bind -n C-M-S-Right resize-pane -R 5

      # Window Navigation
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9
      bind -n M-Left select-window -t -1
      bind -n M-Right select-window -t +1

      # Management
      bind r command-prompt -I "#W" "rename-window -- '%%'"
      bind R command-prompt -I "#S" "rename-session -- '%%'"
      bind K kill-session
      bind P switch-client -p
      bind N switch-client -n

      # Fix Shift+Enter
      bind-key -n S-Enter send-keys Escape "[13;2u"
    '';
  };
}
