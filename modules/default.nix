# Den migration — modules root (ADR-0013).
# Only the entry wires: den.nix (Den + formatter + defaults), aspects.nix
# (host aspects + entity declarations), users.nix (ivokun user aspect).
{
  imports = [
    ./den.nix
    ./aspects.nix
    ./users.nix
  ];
}
