# The flake's pinned Hyprland 0.56.2, adjusted for nixpkgs 26.11.
#
# Two dependencies moved past the versions Hyprland 0.56.2 accepts:
#   * glaze: nixpkgs now ships 9.0.0, but Hyprland's CMake looks for
#     7.x (`find_package(glaze 7...<8)`), then falls back to an impure
#     FetchContent clone. Pin the last 7.x release locally.
#   * hyprtoolkit: hyprland-guiutils resolves hyprtoolkit from its nixpkgs,
#     which now ships 0.6.0 requiring hyprutils >= 0.14.2. Hyprland 0.56.2's
#     lock pins hyprutils 0.14.0, so use the flake's matching 0.5.4 toolkit.
# Both overrides are build/runtime inputs only; the compositor stays 0.56.2.
{
  inputs,
  system,
}: let
  pkgs = inputs.hyprland.inputs.nixpkgs.legacyPackages.${system};

  hyprtoolkit =
    inputs.hyprland.inputs.hyprland-guiutils.inputs.hyprtoolkit.packages.${system}.default;

  hyprland-guiutils = inputs.hyprland.inputs.hyprland-guiutils.packages.${system}.default.override {
    inherit hyprtoolkit;
  };

  glaze-hyprland =
    (pkgs.glaze.override {
      enableSSL = false;
      enableInterop = false;
    })
    .overrideAttrs (_: {
      version = "7.9.1";
      src = pkgs.fetchFromGitHub {
        owner = "stephenberry";
        repo = "glaze";
        tag = "v7.9.1";
        hash = "sha256-NRRq5MGF2f5PW0teYnq58ELzson+U6KHVPaY6r30KLA=";
      };
      # 9.0.0 carries a Qt-macro patch that does not apply to 7.9.1.
      patches = [];
    });
in
  inputs.hyprland.packages.${system}.hyprland.override {
    inherit hyprland-guiutils glaze-hyprland;
  }
