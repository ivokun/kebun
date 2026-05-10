{ pkgs, ... }: {
  services.snapper = {
    cleanupInterval = "1d";
    filters = ''
      # Exclude directories from pre/post snapshot comparisons
      - .cache
      - .local/share/Trash
      - node_modules
      - .git
    '';
  };
}
