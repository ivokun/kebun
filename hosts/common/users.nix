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
      "video"
      "audio"
      "docker"
      "input"
      "storage"
      # Cowork (claude-desktop's QEMU VM) opens /dev/kvm and /dev/vhost-vsock,
      # both owned by group kvm.
      "kvm"
    ];
    shell = pkgs.fish;
    initialPassword = "changeme";
  };

  programs.fish.enable = true;
  programs.zsh.enable = true;

  nix.settings.trusted-users = ["root" "@wheel"];
}
