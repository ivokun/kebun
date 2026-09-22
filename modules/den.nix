# Den entry (ADR-0013).
{
  inputs,
  den,
  lib,
  ...
}: {
  imports = [
    inputs.den.flakeModule
    # Declares flake.packages with merge semantics (den discussion #317).
    # Without it, the two diagram modules' flake.packages.x86_64-linux
    # definitions land on the same freeform attr and one silently wins —
    # diagrams.nix's write-diagrams was being dropped.
    inputs.den.flakeOutputs.packages
  ];

  # Formatter wrapper — alejandra reads STDIN when invoked bare, so `nix fmt`
  # needs a default path (same wrapper as the pre-Den flake).
  flake.formatter.x86_64-linux = let
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  in
    pkgs.writeShellScriptBin "alejandra" ''
      if [ $# -eq 0 ]; then
        set -- .
      fi
      exec ${pkgs.alejandra}/bin/alejandra "$@"
    '';
}
