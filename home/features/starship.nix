{
  config,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;
in {
  programs.starship = {
    enable = true;
    enableTransience = true;

    settings = {
      palette = "rose_pine_dawn";

      palettes.rose_pine_dawn = {
        overlay = palette.overlay;
        love = palette.love;
        gold = palette.gold;
        rose = palette.rose;
        pine = palette.pine;
        foam = palette.foam;
        iris = palette.iris;
        text = palette.text;
        # starship's "muted" is Dawn's subtle #797593 — NOT palette.muted
        # (dark_foreground) or palette.mutedText (inactive_fg). Name clash noted.
        muted = palette.subtle;
      };

      add_newline = true;
      command_timeout = 200;

      format = "$directory$git_branch$git_status\n$character";

      character = {
        success_symbol = "[❯](bold foam)";
        error_symbol = "[❯](bold love)";
      };

      directory = {
        truncation_length = 2;
        truncation_symbol = "…/";
        style = "bold pine";
        repo_root_style = "bold foam";
        repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
        format = "[$path]($style) ";
        read_only = " ro";
        read_only_style = "love";
      };

      git_branch = {
        style = "bold iris";
        format = "[$symbol$branch]($style) ";
        symbol = " ";
      };

      git_status = {
        style = "bold rose";
        conflicted = ''≠''${count} '';
        ahead = ''⇡''${count} '';
        behind = ''⇣''${count} '';
        diverged = ''⇕⇡''${ahead_count}⇣''${behind_count} '';
        untracked = ''?''${count} '';
        stashed = ''⚑''${count} '';
        modified = ''!''${count} '';
        staged = ''+''${count} '';
        renamed = ''»''${count} '';
        deleted = ''✘''${count} '';
      };
    };
  };
}
