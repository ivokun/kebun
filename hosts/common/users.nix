{
  config,
  pkgs,
  username,
  ...
}: {
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "docker"
      "input"
      "storage"
    ];
    shell = pkgs.fish;
    initialPassword = "changeme";
  };

  programs.fish.enable = true;
  programs.zsh.enable = true;

  nix.settings.trusted-users = ["root" "@wheel"];
}
