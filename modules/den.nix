# Den entry (ADR-0013).
{
  inputs,
  den,
  lib,
  ...
}: {
  imports = [inputs.den.flakeModule];

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
