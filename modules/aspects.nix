# Den migration — host aspects & wiring (ADR-0013).
# The former hosts/common modules are plain NixOS modules under aspects/ and
# are captured here as aspect imports. Like the pre-Den flake, the
# username/hostname/system fn args those modules request are delivered via
# nixosSystem specialArgs and home-manager extraSpecialArgs, applied here
# with standalone hosts.batteries (define-user handles the user side).
{
  den,
  inputs,
  lib,
  ...
}: {
  # ─── Shared host aspects ───
  den.aspects.core.nixos.imports = [
    ./aspects/core.nix
    inputs.nix-index-database.nixosModules.nix-index
  ];
  den.aspects.desktop.nixos.imports = [./aspects/desktop.nix];
  den.aspects.dev.nixos.imports = [./aspects/dev.nix];
  den.aspects.networking.nixos.imports = [./aspects/networking.nix];
  den.aspects.printing.nixos.imports = [./aspects/printing.nix];
  den.aspects.snapper.nixos.imports = [./aspects/snapper.nix];

  # Host-free shell settings from the former hosts/common/users.nix.
  den.aspects.shell-entry.nixos = {
    programs.fish.enable = true;
    programs.zsh.enable = true;
  };

  # ─── Host aspect: sakura ───
  den.aspects.sakura = {
    includes = [
      den.aspects.core
      den.aspects.desktop
      den.aspects.dev
      den.aspects.networking
      den.aspects.printing
      den.aspects.snapper
      den.aspects.shell-entry
      den.batteries.hostname
    ];

    nixos = {host, ...}: {
      imports = [../hosts/sakura];

      networking.hostName = host.hostName;

      # NixOS-module fn args consumed by hosts/sakura (and the shared common
      # modules below) — mirrors the pre-Den flake's specialArgs.
      _module.args.inputs = inputs;

      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "hm-backup";

      nixpkgs.overlays = [
        (final: prev: {
          deno = prev.deno.overrideAttrs (old: {
            checkFlags =
              (old.checkFlags or [])
              ++ [
                "--skip"
                "uv_compat::tests::tty_reset_mode_restores_termios"
              ];
          });
        })
        (import ../lib/opencode-overlay.nix)
      ];
    };
  };

  # ─── Entity wiring: sakura host, ivokun user with homeManager ───
  den.hosts.x86_64-linux.sakura.users.ivokun = {
    classes = ["homeManager"];
  };

  den.schema.user.classes = lib.mkDefault ["homeManager"];

  # ─── Defaults (stateVersion) ───
  den.default.nixos.system.stateVersion = "25.05";
  den.default.homeManager.home.stateVersion = "25.05";
}
