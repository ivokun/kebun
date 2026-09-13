# Den migration — host aspects & wiring (ADR-0013).
# hosts/common/*.nix are kept as plain NixOS modules and captured here as
# aspect imports — their bodies are untouched. Like the pre-Den flake, the
# username/hostname/system fn args those modules request are delivered via
# nixosSystem specialArgs and home-manager extraSpecialArgs, applied here
# with standalone hosts.batteries (define-user handles the user side).
{
  den,
  inputs,
  lib,
  ...
}: {
  # ─── Shared host aspects (1:1 from hosts/common/) ───
  den.aspects.core.nixos.imports = [
    ./aspects/core.nix
    inputs.nix-index-database.nixosModules.nix-index
  ];
  den.aspects.desktop.nixos.imports = [./aspects/desktop.nix];
  den.aspects.dev.nixos.imports = [./aspects/dev.nix];
  den.aspects.networking.nixos.imports = [./aspects/networking.nix];
  den.aspects.printing.nixos.imports = [./aspects/printing.nix];
  den.aspects.snapper.nixos.imports = [./aspects/snapper.nix];

  # The host-free settings from hosts/common/users.nix.
  den.aspects.shell-entry.nixos = {
    programs.fish.enable = true;
    programs.zsh.enable = true;

    nix.settings.trusted-users = ["root" "@wheel"];
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
          # opencode 1.18.11, backported from NixOS/nixpkgs@9d590febde.
          # The pinned nixos-unstable eval (2026-08-01) still carries 1.18.4.
          # Drop this override once the channel advances past the bump.
          opencode = prev.opencode.overrideAttrs (old: rec {
            version = "1.18.11";
            src = prev.fetchFromGitHub {
              owner = "anomalyco";
              repo = "opencode";
              tag = "v${version}";
              hash = "sha256-Rg+NeRLeu0e+WSTZd8oJzV3XMMxXZCZ5LImDcCraX8g=";
            };
            node_modules = old.node_modules.overrideAttrs (_: {
              inherit version src;
              outputHash = "sha256-lHr4g4Kw9CvyDHiuyuCDsyk9vOXzz/My5bI9/zd5aYE=";
            });
          });
        })
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
