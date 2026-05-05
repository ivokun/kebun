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
      resurrect
      continuum
      rose-pine
      yank
      battery
      vim-tmux-navigator
    ];

    extraConfig = ''
      # Continuum & Resurrect settings
      set -g @continuum-restore on
      set -g @continuum-save-interval 10
      set -g @resurrect-capture-pane-contents on
      set -g @resurrect-strategy-nvim session

      # General Settings
      set-option -g default-shell ${pkgs.fish}/bin/fish
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

      # Copy mode (Vi style)
      setw -g mode-keys vi
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel

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

      # Vim-Tmux navigator
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\S+\/)?g?(view|n?vim?x?)(diff)?$'"
      bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "select-pane -L"
      bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "select-pane -D"
      bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "select-pane -U"
      bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "select-pane -R"

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

      # Rose Pine Dawn theme for tmux status bar
      set-option -g status-style bg=#EFE9E2,fg=colour241
      set-window-option -g window-status-current-style bg=#EFE9E2,fg=colour223
      set-window-option -g window-status-separator ""
      set-window-option -g window-status-format "#[bg=colour239,fg=colour246] #I  #W #[bg=#EFE9E2,fg=colour239]"
      set-window-option -g window-status-current-format "#[bg=colour208,fg=colour235] #I  #W #[bg=#EFE9E2,fg=colour208]"
      set-option -g pane-active-border-style fg=colour24,bg=#EFE9E2
      set-option -g status-left-length 80
      set-option -g status-right-length 80
      set-option -g status-left "#[bg=colour241,fg=colour248] #S #[bg=#EFE9E2,fg=colour241]"
      set-option -g status-right "#[bg=#EFE9E2,fg=colour239]#[bg=colour239,fg=colour246] %Y-%m-%d  %H:%M #{battery_color_fg}#[bg=colour239]#{battery_color_bg}#[fg=colour223] #{battery_percentage} "
    '';
  };
}
