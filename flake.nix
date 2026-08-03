{
  description = "Kebun — NixOS garden configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nh — Nix Helper for rebuilds
    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Walker and its elephant backend come from nixpkgs, which carries them as a
    # co-maintained pair plus a working services.elephant module. As flake
    # inputs the two versions had to be paired by hand, and walker's own module
    # collided with the nixpkgs one over services.elephant.

    # Nix-index database for command-not-found
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    hyprland,
    nh,
    nix-index-database,
    ...
  } @ inputs: let
    systems = {
      sakura = {
        system = "x86_64-linux";
        hostname = "sakura";
        username = "ivokun";
      };
    };

    sharedModules = [
      ./hosts/common/core.nix
      ./hosts/common/desktop.nix
      ./hosts/common/dev.nix
      ./hosts/common/networking.nix
      ./hosts/common/users.nix
      ./hosts/common/printing.nix
      ./hosts/common/snapper.nix
      nix-index-database.nixosModules.nix-index
    ];

    mkHomeManagerModules = {username, ...}: [
      {
        home-manager.users.${username} = {
          imports = [
            ./home/common.nix
            ./home/sakura.nix
            ./home/features/hyprland.nix
            ./home/features/waybar.nix
            ./home/features/terminals.nix
            ./home/features/shell.nix
            ./home/features/starship.nix
            ./home/features/fish.nix
            ./home/features/editors.nix
            ./home/features/theme-rose-pine.nix
            ./home/features/fcitx5.nix
            ./home/features/btop.nix
            ./home/features/fastfetch.nix
            ./home/features/ghostty.nix
            ./home/features/kitty.nix
            ./home/features/opencode.nix
            ./home/features/helix.nix
            ./home/features/mpv.nix
            ./home/features/webapps.nix
          ];
        };
      }
    ];

    mkSystem = name: cfg: let
      inherit (cfg) system hostname username;
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs username hostname system;};
        modules =
          sharedModules
          ++ [
            ./hosts/${hostname}
            home-manager.nixosModules.home-manager
            {
              home-manager.extraSpecialArgs = {inherit inputs username hostname system;};
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
            }
          ]
          ++ mkHomeManagerModules cfg;
      };
  in {
    nixosConfigurations = nixpkgs.lib.mapAttrs mkSystem systems;

    # Allow `nix fmt` to work
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
  };
}
