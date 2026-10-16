{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  palette = import ../../lib/palette.nix;

  # resurrect's save script, triggerable from outside tmux.
  #
  # It is handed to the server via run-shell rather than executed here, so it
  # inherits the session environment — the same context continuum's own
  # auto-save runs in. Executed directly from a systemd unit it would instead
  # get the unit's bare environment, where `hostname`, `bash` (resurrect's
  # helper scripts carry unpatched `#!/usr/bin/env bash` shebangs) and `ps` are
  # all missing, and — the silent one — no UTF-8 locale is set, which makes
  # tmux 3.7 render the tab delimiter of `list-panes -F` as `_`. Every field
  # then parses empty, every pane is skipped as belonging to a grouped session,
  # and the resulting 9-byte file takes over the `last` symlink that restore
  # reads. Verified 2026-10-15: run-shell from `env -i` saves all three panes.
  tmux-resurrect-save = pkgs.writeShellApplication {
    name = "tmux-resurrect-save";
    runtimeInputs = [config.programs.tmux.package];
    text = ''
      # No server, or a server with no sessions, means no state to save — and
      # not a failure. The guard also keeps run-shell from spawning a server
      # just to save an empty layout over a good one.
      if ! tmux has-session 2>/dev/null; then
        exit 0
      fi
      exec tmux run-shell \
        "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh quiet"
    '';
  };
in {
  # ─── Neovim ───
  # LazyVim is best managed outside home-manager since it manages its own plugins.
  # We source the full LazyVim starter + custom configs from the repo.
  # withRuby/withPython3 stay at their (default) true value — pinned explicitly
  # because HM now warns about relying on the defaults.
  programs.neovim = {
    enable = true;
    withRuby = true;
    withPython3 = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    # Native tools for both hosts. The audited Mason LuaLS/StyLua binaries
    # require a conventional Linux ELF loader that is absent on NixOS.
    # lspconfig.lua marks the native LSPs mason=false; plugins.lua filters
    # the native tools and appends Mason's PATH so retained installs cannot
    # shadow these Nix packages.
    # yarn + nodejs feed markdown-preview.nvim's `cd app && yarn install`
    # build hook. Scoped to the nvim wrapper PATH — no globals, no nix-ld.
    extraPackages = with pkgs; [
      lua-language-server
      stylua
      rust-analyzer
      yarn
      nodejs
    ];
  };

  home.file.".config/nvim" = {
    source = ../nvim;
    recursive = true;
  };

  # ─── Git ───
  # userName/userEmail/aliases/extraConfig migrated to programs.git.settings
  # (HM deprecation) — rendered output is the same .gitconfig via toGitINI.
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Salahuddin Muhammad Iqbal";
        email = "salahuddin.mi@gmail.com";
      };

      alias = {
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status";
        lg = "log --oneline --graph --decorate --all";
        last = "log -1 HEAD";
        unstage = "reset HEAD --";
        amend = "commit --amend";
      };

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
    settings = {
      gui.theme = {
        activeBorderColor = [palette.foam "bold"];
        inactiveBorderColor = [palette.subtle];
        optionsTextColor = [palette.iris];
        selectedLineBgColor = [palette.overlay];
        selectedRangeBgColor = [palette.overlay];
        cherryPickedCommitBgColor = [palette.foam];
        cherryPickedCommitFgColor = [palette.background];
        unstagedChangesColor = [palette.love];
        defaultFgColor = [palette.text];
        searchingActiveBorderColor = [palette.gold];
      };
    };
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
      # continuum must load last: it prepends its save script to status-right,
      # and any status-setting plugin loaded after it (rose-pine) would clobber
      # the interpolation, silently disabling auto-save.
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore on
          set -g @continuum-save-interval 10
        '';
      }
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

      # Prefix (C-Space; C-b kept as secondary — matches upstream config/tmux/tmux.conf)
      set -g prefix C-Space
      set -g prefix2 C-b
      bind -N "Send prefix" C-Space send-prefix

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


    '';
  };

  # ─── tmux session persistence across reboots ───
  # continuum restores on its own (@continuum-restore on, above): a freshly
  # started server re-runs resurrect's restore script. Saving is the weak half.
  # continuum auto-saves by prepending an interpolation to status-right, so a
  # save only happens when the status line redraws — i.e. only while a client
  # is attached, and only every @continuum-save-interval minutes. A detached
  # server never saves at all, and a shutdown discards everything since the
  # last tick.
  #
  # These units trigger a save explicitly instead. TMUX_TMPDIR is
  # pinned to %t because programs.tmux.secureSocket puts the socket under
  # /run/user/$UID; the unit must not depend on the session env being imported.
  systemd.user.services.tmux-resurrect-save = {
    Unit.Description = "Save tmux sessions (tmux-resurrect)";
    Service = {
      Type = "oneshot";
      Environment = "TMUX_TMPDIR=%t";
      ExecStart = lib.getExe tmux-resurrect-save;
    };
  };

  # The reliability floor: saves on a fixed cadence whether or not a client is
  # attached, so a shutdown can lose at most two minutes of layout.
  systemd.user.timers.tmux-resurrect-save = {
    Unit.Description = "Save tmux sessions periodically";
    Timer = {
      OnStartupSec = "2m";
      OnUnitActiveSec = "2m";
    };
    Install.WantedBy = ["timers.target"];
  };

  # One last save as the session is torn down, catching the gap since the last
  # timer tick. Best-effort by nature: the tmux server lives in the app scope
  # of whichever terminal spawned it, and systemd stops that scope without any
  # ordering against this unit. After=graphical-session.target biases the
  # teardown order in our favour (units stop in reverse), it does not guarantee
  # it — the timer above, not this hook, is what makes the state survive.
  systemd.user.services.tmux-resurrect-save-on-exit = {
    Unit = {
      Description = "Save tmux sessions when the user session ends";
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = "TMUX_TMPDIR=%t";
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = lib.getExe tmux-resurrect-save;
      TimeoutStopSec = 20;
    };
    Install.WantedBy = ["default.target"];
  };
}
