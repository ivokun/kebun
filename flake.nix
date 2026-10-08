{
  # Den entrypoint (ADR-0013). Outputs are produced by Den's evaluation
  # pipeline from modules/.
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

    # Schema library behind den's aspect resolution (den.lib.schema). Pinned
    # to the exact rev in den's CI lock — its no-input fallback — so declaring
    # the input keeps den off the impure builtins.fetchTarball fallback.
    gen-schema = {
      url = "github:sini/gen-schema/4bd0f6eb1799bf3c38eb3707419157b1f70eb1f5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-index database for command-not-found
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Mission control for AI coding agents. Pin release tags deliberately;
    # home/common.nix installs the package for every managed host.
    luvus = {
      url = "github:RizRiyz/luvus/v0.14.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
