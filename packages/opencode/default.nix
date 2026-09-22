# OpenCode MCP packaging: every local MCP server in
# home/opencode/opencode.json runs from a Nix-store executable — nothing
# is fetched via npx/uvx at launch.
#
# - mcp-server-memory and mcp-nixos come from pinned nixpkgs. Sequential
#   thinking 2026.8.31 and github-mcp-server 1.12.2 are reproducible security/
#   compatibility backports in this directory.
# - browsermcp and gitnexus are packed from their npm registry tarballs
#   with lockfile-pinned dependency trees (./*.nix + ./*-package-lock.json).
# - the `opencode` wrapper pins command resolution to pkgs.opencode, disables
#   self-updates, and removes ambient GitHub credentials before any plugin or
#   tool runs.
# - opencode-github-mcp obtains the GitHub token per launch via
#   `gh auth token` and explicitly injects it only into that server's wiped
#   environment (`env -i`). This is environment hygiene, not isolation from
#   other processes running as the same user and able to query the keyring.
{pkgs}: let
  browsermcp = pkgs.callPackage ./browsermcp.nix {};
  gitnexus = pkgs.callPackage ./gitnexus.nix {};
  githubMcpServer = pkgs.callPackage ./github-mcp-server.nix {};
  sequentialThinking = pkgs.callPackage ./sequential-thinking.nix {};
  whisperopencodePush = pkgs.callPackage ./whisperopencode-push.nix {};

  # Excalidraw MCP dist (prebuilt bundle from the repo) kept in the Nix
  # store; nothing is deployed under ~/.config/opencode/mcp any more.
  excalidrawMcpDist = pkgs.runCommand "opencode-excalidraw-mcp-dist" {} ''
    mkdir -p $out
    cp -r ${../../home/opencode/mcp/excalidraw-mcp/dist}/. $out/
  '';
  # mcp-server-memory and mcp-server-sequential-thinking each install the
  # full @modelcontextprotocol/servers mono-repo tree in nixpkgs, which
  # collides when both land in one home.packages buildEnv. Only their bin
  # wrappers need to be on PATH (each wrapper execs its own store path), so
  # expose a link farm of the four MCP server executables instead.
  mcp-servers = pkgs.runCommand "opencode-mcp-servers" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.mcp-server-memory}/bin/mcp-server-memory $out/bin/mcp-server-memory
    ln -s ${sequentialThinking}/bin/mcp-server-sequential-thinking $out/bin/mcp-server-sequential-thinking
    ln -s ${pkgs.mcp-nixos}/bin/mcp-nixos $out/bin/mcp-nixos
    ln -s ${githubMcpServer}/bin/github-mcp-server $out/bin/github-mcp-server
  '';
in {
  inherit
    browsermcp
    gitnexus
    githubMcpServer
    mcp-servers
    sequentialThinking
    whisperopencodePush
    ;

  # Keep the V2 config/plugin surface coupled to the exact Nix package. An
  # unmanaged ~/.opencode/bin installation must never shadow this command,
  # and upgrades happen through this repository rather than OpenCode itself.
  opencode = pkgs.writeShellScriptBin "opencode" ''
    case "''${1:-}" in
      update | upgrade)
        echo "OpenCode is managed by Nix; update packages/opencode/opencode-v2.nix and rebuild instead." >&2
        exit 1
        ;;
    esac

    exec ${pkgs.coreutils}/bin/env \
      -u GITHUB_TOKEN \
      -u GH_TOKEN \
      -u GITHUB_PERSONAL_ACCESS_TOKEN \
      -u GITHUB_ENTERPRISE_TOKEN \
      -u GH_ENTERPRISE_TOKEN \
      OPENCODE_DISABLE_AUTOUPDATE=1 \
      ${pkgs.opencode}/bin/opencode "$@"
  '';

  opencode-excalidraw-mcp = pkgs.writeShellScriptBin "opencode-excalidraw-mcp" ''
    exec ${pkgs.coreutils}/bin/env \
      -u GITHUB_TOKEN \
      -u GH_TOKEN \
      -u GITHUB_PERSONAL_ACCESS_TOKEN \
      -u GITHUB_ENTERPRISE_TOKEN \
      -u GH_ENTERPRISE_TOKEN \
      ${pkgs.nodejs}/bin/node "${excalidrawMcpDist}/index.js" "$@"
  '';

  # Official local github-mcp-server instead of the remote Copilot
  # endpoint. The token is fetched per launch from the gh keyring; the wrapper
  # injects a token variable only into this child. Same-user processes remain
  # able to query the unlocked keyring independently. MCP access is read-only,
  # limited to the four toolsets used for repository/issue/PR inspection, and
  # lockdown-filtered to reduce prompt injection from untrusted public content.
  opencode-github-mcp = pkgs.writeShellScriptBin "opencode-github-mcp" ''
    token="$(${pkgs.coreutils}/bin/env \
      -u GITHUB_TOKEN \
      -u GH_TOKEN \
      -u GITHUB_PERSONAL_ACCESS_TOKEN \
      -u GITHUB_ENTERPRISE_TOKEN \
      -u GH_ENTERPRISE_TOKEN \
      GH_NO_UPDATE_NOTIFIER=1 \
      GH_PROMPT_DISABLED=1 \
      ${pkgs.gh}/bin/gh auth token --hostname github.com)" || exit 1
    exec ${pkgs.coreutils}/bin/env -i \
      HOME="''${HOME:-}" \
      SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      GITHUB_PERSONAL_ACCESS_TOKEN="$token" \
      ${githubMcpServer}/bin/github-mcp-server \
        --lockdown-mode \
        --read-only \
        --toolsets=repos,issues,pull_requests,users \
        stdio "$@"
  '';
}
