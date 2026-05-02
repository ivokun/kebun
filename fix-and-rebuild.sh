#!/usr/bin/env bash
set -euo pipefail

FLAKE_PATH="$(cd "$(dirname "$0")" && pwd)"
HOST="sakura"

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
