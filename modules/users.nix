# Den migration — user aspect ivokun (ADR-0013).
# Home Manager modules (home/**) are imported untouched into the user
# aspect's homeManager class. Their username/system/inputs function args are
# satisfied via _module.args on that class — the module-system level, which
# den's home-manager battery does not clash with (extraSpecialArgs is
# reserved by the battery for osConfig).
{
  den,
  inputs,
  lib,
  ...
}: {
  den.aspects.ivokun = {
    includes = [
      den.batteries.define-user
    ];

    # OS-level user definition (the former hosts/common/users.nix block;
    # the free-standing programs.fish/zsh live in den.aspects.shell-entry,
    # while Nix daemon trust policy lives in the core aspect). No primary-user
    # battery: iwd replaces
    # NetworkManager on this host, so the battery's networkmanager group
    # would point at a daemon that is deliberately disabled.
    nixos = {
      user,
      pkgs,
      ...
    }: {
      users.users.${user.userName} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          # Cowork (claude-desktop's QEMU VM) opens /dev/kvm and
          # /dev/vhost-vsock, both owned by group kvm.
          "kvm"
        ];
        shell = pkgs.fish;

        # Passwords stay mutable and are set interactively (`passwd ivokun`)
        # after installation; never place a reusable password in the Nix store.
        # A fresh account remains locked until that interactive step.
        initialHashedPassword = "!";
        # Administrative SSH is key-only and restricted to tailscale0 by the
        # networking aspect. This is the operator key on IVOKUN-HTPC.
        openssh.authorizedKeys.keyFiles = [../keys/ivokun-htpc.pub];
      };

      # Keep privilege elevation password-gated even if the upstream default
      # changes. `wheel` remains intentional for local administration.
      security.sudo.wheelNeedsPassword = true;
    };

    # Home Manager config for this user — all original home/ modules, with
    # their fn args (username/system/inputs) supplied at module level.
    homeManager = {
      config,
      hm,
      ...
    }: {
      imports = [
        ../home/common.nix
        ../home/sakura.nix
        ../home/features/hyprland.nix
        ../home/features/omarchy-shell.nix
        ../home/features/terminals.nix
        ../home/features/shell.nix
        ../home/features/starship.nix
        ../home/features/fish.nix
        ../home/features/editors.nix
        ../home/features/theme-rose-pine.nix
        ../home/features/fcitx5.nix
        ../home/features/btop.nix
        ../home/features/fastfetch.nix
        ../home/features/ghostty.nix
        ../home/features/kitty.nix
        ../home/features/opencode.nix
        ../home/features/helix.nix
        ../home/features/mpv.nix
        ../home/features/webapps.nix
        ../home/features/sleep-lock.nix
      ];
      _module.args.username = lib.mkForce "ivokun";
      _module.args.system = lib.mkForce "x86_64-linux";
      _module.args.inputs = lib.mkForce inputs;
    };
  };
}
