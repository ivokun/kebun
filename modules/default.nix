# Den migration — modules root (ADR-0013).
# Entry wiring: den.nix (Den + formatter + defaults), aspects.nix (host
# aspects + entity declarations), users.nix (ivokun user aspect),
# diagrams.nix (den-diagram rendering, opt-in via `nix run .#write-diagrams`).
{
  imports = [
    ./den.nix
    ./aspects.nix
    ./users.nix
    ./diagrams.nix
  ];
}
