{
  config,
  lib,
  pkgs,
  username,
  ...
}: {
  # ─── Neovim ───
  # LazyVim is best managed outside home-manager since it manages its own plugins.
  # Just ensure nvim is installed and the config directory is linked.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
  };

  # ─── IMPORTANT: Neovim memory watchdog ───
  # The current Arch setup has critical memory watchdog autocmds that prevent
  # nvim from consuming 6-21GB RAM and crashing the system.
  # After copying your LazyVim config from backup, add this to:
  #   ~/.config/nvim/lua/config/autocmds.lua
  #
  # -- Memory watchdog
  # vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
  #   callback = function()
  #     local mem = collectgarbage("count") / 1024
  #     if mem > 2000 then
  #       -- Disable treesitter on large files / JSON
  #       vim.cmd("TSDisable highlight")
  #       vim.cmd("TSDisable indent")
  #       collectgarbage("collect")
  #     elseif mem > 1000 then
  #       vim.notify("Memory warning: " .. math.floor(mem) .. "MB", vim.log.levels.WARN)
  #     end
  #   end,
  # })
  #
  # -- Force GC on buffer delete
  # vim.api.nvim_create_autocmd("BufDelete", {
  #   callback = function()
  #     collectgarbage("collect")
  #   end,
  # })

  # ─── btop Rose Pine Dawn theme ───
  # After installing, run: btop --config
  # Then set theme = "rose-pine-dawn" in ~/.config/btop/btop.conf
  # Or create the theme file:
  home.file.".config/btop/themes/rose-pine-dawn.theme".text = ''
    # Main background, empty for terminal default, need to be empty if you want transparent background
    theme[main_bg]="#faf4ed"

    # Main text color
    theme[main_fg]="#575279"

    # Title color for boxes
    theme[title]="#56949f"

    # Highlight color for keyboard shortcuts
    theme[hi_fg]="#b4637a"

    # Background color of selected items
    theme[selected_bg]="#f2e9e1"

    # Foreground color of selected items
    theme[selected_fg]="#575279"

    # Color of inactive/disabled text
    theme[inactive_fg]="#9893a5"

    # Color of graph lines
    theme[graph_1]="#56949f"
    theme[graph_2]="#907aa9"
    theme[graph_3]="#ea9d34"
    theme[graph_4]="#d7827e"
    theme[graph_5]="#286983"
    theme[graph_6]="#b4637a"

    # CPU graph colors
    theme[cpu_user]="#56949f"
    theme[cpu_system]="#b4637a"
    theme[cpu_nice]="#907aa9"
    theme[cpu_idle]="#9893a5"
    theme[cpu_iowait]="#ea9d34"
    theme[cpu_irq]="#d7827e"
    theme[cpu_softirq]="#286983"
    theme[cpu_steal]="#b4637a"
    theme[cpu_guest]="#575279"

    # Mem graph colors
    theme[mem_used]="#56949f"
    theme[mem_cached]="#907aa9"
    theme[mem_available]="#9893a5"
    theme[mem_free]="#f2e9e1"

    # Proc box colors
    theme[proc_box]="#56949f"
    theme[proc_misc]="#9893a5"

    # Net graph colors
    theme[net_upload]="#b4637a"
    theme[net_download]="#56949f"

    # Battery colors
    theme[battery_high]="#286983"
    theme[battery_mid]="#ea9d34"
    theme[battery_low]="#b4637a"
  '';

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
      tmux-resurrect
      tmux-continuum
      tmux-battery
      vim-tmux-navigator
      tmux-yank
    ];

    extraConfig = ''
      # Continuum & Resurrect settings
      set -g @continuum-restore on
      set -g @continuum-save-interval 10
      set -g @resurrect-capture-pane-contents on
      set -g @resurrect-strategy-nvim session

      # General Settings
      set-option -g default-shell ${pkgs.zsh}/bin/zsh
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
