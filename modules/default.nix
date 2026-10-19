# Den migration — modules root (ADR-0013).
# Entry wiring: den.nix (Den + formatter + defaults), aspects.nix (host
# aspects + entity declarations), users.nix (ivokun user aspect),
# opencode-memory.nix (host-independent memory artifacts), diagrams.nix
# (den-diagram rendering, opt-in via `nix run .#write-diagrams`).
{
  imports = [
    ./den.nix
    ./aspects.nix
    ./users.nix
    ./opencode-memory.nix
    ./diagrams.nix
    ./diagrams-mermaid.nix
  ];
}
