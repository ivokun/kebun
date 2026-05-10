{ config, pkgs, ... }: {
  programs.starship = {
    enable = true;
    enableTransience = true;

    settings = {
      palette = "rose_pine_dawn";

      palettes.rose_pine_dawn = {
        overlay = "#f2e9e1";
        love    = "#b4637a";
        gold    = "#ea9d34";
        rose    = "#d7827e";
        pine    = "#286983";
        foam    = "#56949f";
        iris    = "#907aa9";
        text    = "#575279";
        muted   = "#797593";
      };

      add_newline = true;
      command_timeout = 200;

      format = "$directory$git_branch$git_status\n$character";

      character = {
        success_symbol = "[❯](bold foam)";
        error_symbol   = "[❯](bold love)";
      };

      directory = {
        truncation_length  = 2;
        truncation_symbol  = "…/";
        style               = "bold pine";
        repo_root_style     = "bold foam";
        repo_root_format    = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
        format              = "[$path]($style) ";
        read_only           = " ro";
        read_only_style     = "love";
      };

      git_branch = {
        style  = "bold iris";
        format = "[$symbol$branch]($style) ";
        symbol = " ";
      };

      git_status = {
        style = "bold rose";
        conflicted  = ''≠''${count} '';
        ahead       = ''⇡''${count} '';
        behind      = ''⇣''${count} '';
        diverged    = ''⇕⇡''${ahead_count}⇣''${behind_count} '';
        untracked   = ''?''${count} '';
        stashed     = ''⚑''${count} '';
        modified    = ''!''${count} '';
        staged      = ''+''${count} '';
        renamed     = ''»''${count} '';
        deleted     = ''✘''${count} '';
      };
    };
  };
}
