{
  # Den entrypoint (ADR-0013). Inputs unchanged; outputs are now produced by
  # Den's evaluation pipeline from modules/.
  outputs = inputs @ {self, ...}:
    (inputs.nixpkgs.lib.evalModules {
      modules = [
        inputs.den.flakeModule
        ./modules
      ];
      specialArgs = {inherit inputs self;};
    }).config.flake;

  inputs = {
    # Den — aspect-oriented resolution framework (ADR-0013).
    den.url = "github:denful/den";

    # Aspect-resolution diagram renderer (den-diagram).
    den-diagram.url = "github:denful/den-diagram";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pinned to the Quattro migration target (ADR-0007 Stage 1): v4's Lua config
    # layer requires 0.56+, and 0.56.0/0.56.1 emitted invalid `hyprctl -j binds`
    # JSON. Bump the ref deliberately, not via a blanket flake update.
    hyprland = {
      url = "github:hyprwm/Hyprland?ref=v0.56.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nh — Nix Helper for rebuilds
    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-index database for command-not-found
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
