#!/usr/bin/env bash
set -euo pipefail

FLAKE_PATH="$(cd "$(dirname "$0")" && pwd)"
HOST="sakura"

# Self-test: run the nix.conf sed repairs against a representative fixture in
# a private temporary directory (no sudo, no rebuild) so the expressions can
# be verified without touching the live config. Exits 0 on pass, 1 on failure.
if [[ "${1:-}" == "--self-test" ]]; then
  testdir="$(mktemp -d)"
  fixture="$testdir/nix.conf"
  want="$testdir/expected"
  printf 'trusted-public-keys = cache.nixos.org-1:6NCHdD59x4g^{hash}= hyprland.cachix.org-1:a7pgxQMzO+MR^{hash}= other-key-1:abc=\n' > "$fixture"
  # Expected byte-exact result: the placeholder cache key is deleted (the
  # whitespace that surrounded it remains — token-level removal, by design)
  # and the hyprland placeholder is substituted with the real key in place.
  printf 'trusted-public-keys =  hyprland.cachix.org-1:a7pgxQMzO+MR5HsMYwJfn+BFMQjEnJPSIlWM+NLSo60= other-key-1:abc=\n' > "$want"

  sed -i \
    -e 's/cache\.nixos\.org-1:6NCHdD59x4g\^{hash}=//g' \
    -e 's/hyprland\.cachix\.org-1:a7pgxQMzO+MR\^{hash}=/hyprland.cachix.org-1:a7pgxQMzO+MR5HsMYwJfn+BFMQjEnJPSIlWM+NLSo60=/g' \
    "$fixture"

  if cmp -s "$fixture" "$want"; then
    echo "self-test: PASS — placeholder keys removed/substituted exactly as intended"
    rm -rf "$testdir"
    exit 0
  else
    echo "self-test: FAIL — got: $(cat "$fixture")" >&2
    echo "self-test: FAIL — wanted: $(cat "$want")" >&2
    rm -rf "$testdir"
    exit 1
  fi
fi

if [[ "$(hostname -s)" != "$HOST" ]]; then
  echo "Refusing to rebuild $HOST from $(hostname -s)." >&2
  echo "Run this emergency script locally on $HOST; --self-test is safe anywhere." >&2
  exit 1
fi

echo "=== Step 1: Fixing broken placeholder keys in /etc/nix/nix.conf ==="
sudo sed -i \
  -e 's/cache\.nixos\.org-1:6NCHdD59x4g\^{hash}=//g' \
  -e 's/hyprland\.cachix\.org-1:a7pgxQMzO+MR\^{hash}=/hyprland.cachix.org-1:a7pgxQMzO+MR5HsMYwJfn+BFMQjEnJPSIlWM+NLSo60=/g' \
  /etc/nix/nix.conf
echo "Done. Current trusted-public-keys:"
grep trusted-public-keys /etc/nix/nix.conf

echo ""
echo "=== Step 2: Rebuilding NixOS ==="
sudo nixos-rebuild switch --flake "${FLAKE_PATH}#${HOST}"

echo ""
echo "=== Done! Reboot or re-login for Hyprland changes to take effect. ==="
