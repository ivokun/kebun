{
  lib,
  pkgs,
  ...
}: let
  opencodeDir = ../opencode;
  opencodePkgs = import ../../packages/opencode {inherit pkgs;};
  managedOpencode = opencodePkgs.opencode;
  mcpServers = opencodePkgs.mcp-servers;
  whisperopencodePush = opencodePkgs.whisperopencodePush;
  sourceConfig = builtins.fromJSON (builtins.readFile (opencodeDir + "/opencode.json"));
  sourceServers = sourceConfig.mcp.servers;

  githubTokenVariables = [
    "GITHUB_TOKEN"
    "GH_TOKEN"
    "GITHUB_PERSONAL_ACCESS_TOKEN"
    "GITHUB_ENTERPRISE_TOKEN"
    "GH_ENTERPRISE_TOKEN"
  ];
  expectedLocalMcpNames = lib.sort builtins.lessThan [
    "browser"
    "excalidraw"
    "github"
    "gitnexus"
    "memory"
    "nixos"
    "sequential-thinking"
  ];
  localMcpNames = lib.sort builtins.lessThan (builtins.attrNames (
    lib.filterAttrs (_name: server: server.type == "local") sourceServers
  ));
  sanitizedCommand = variables: executable: arguments:
    ["${pkgs.coreutils}/bin/env"]
    ++ lib.concatMap (variable: ["-u" variable]) variables
    ++ [executable]
    ++ arguments;

  # Keep the readable source config free of machine-specific store paths, then
  # render every local MCP command with absolute Nix-store executables. This
  # prevents an earlier PATH entry from substituting a different `env`, MCP
  # server, or GitNexus binary at runtime.
  renderedConfig = assert lib.assertMsg (localMcpNames == expectedLocalMcpNames)
  "Every local OpenCode MCP server must receive an absolute command in home/features/opencode.nix";
    sourceConfig
    // {
      mcp =
        sourceConfig.mcp
        // {
          servers =
            sourceServers
            // {
              excalidraw =
                sourceServers.excalidraw
                // {
                  command = [
                    "${opencodePkgs.opencode-excalidraw-mcp}/bin/opencode-excalidraw-mcp"
                    "--stdio"
                  ];
                };
              github =
                sourceServers.github
                // {
                  command = ["${opencodePkgs.opencode-github-mcp}/bin/opencode-github-mcp"];
                };
              memory =
                sourceServers.memory
                // {
                  command = sanitizedCommand githubTokenVariables "${mcpServers}/bin/mcp-server-memory" [];
                };
              sequential-thinking =
                sourceServers.sequential-thinking
                // {
                  command = sanitizedCommand githubTokenVariables "${mcpServers}/bin/mcp-server-sequential-thinking" [];
                };
              browser =
                sourceServers.browser
                // {
                  command = sanitizedCommand githubTokenVariables "${opencodePkgs.browsermcp}/bin/mcp-server-browsermcp" [];
                };
              nixos =
                sourceServers.nixos
                // {
                  command = sanitizedCommand (["PYTHONPATH"] ++ githubTokenVariables) "${mcpServers}/bin/mcp-nixos" [];
                };
              gitnexus =
                sourceServers.gitnexus
                // {
                  command = sanitizedCommand githubTokenVariables "${opencodePkgs.gitnexus}/bin/gitnexus" ["mcp"];
                };
            };
        };
    };
in {
  # Nested Home Manager has its own package set; apply the same OpenCode
  # V2 package as the host so the managed wrapper and config cannot drift.
  nixpkgs.overlays = [(import ../../lib/opencode-overlay.nix)];

  # ─── Opencode configuration ───
  # Deploys opencode agent configs, prompts, skills, plugins, and MCP servers
  # to ~/.config/opencode/ via home-manager.
  #
  # The managed wrapper pins OpenCode to pkgs.opencode (currently 2.0.12),
  # disables self-updates, and
  # strips ambient GitHub credentials before plugins or tools run. Its exact
  # store bin is prepended to PATH so ~/.opencode/bin or mise cannot shadow it.
  #
  # Every local MCP server runs from an absolute Nix-store executable — no
  # PATH lookup and no npx/uvx
  # downloads at launch (packages/opencode/default.nix: pinned nixpkgs and
  # release backports via the mcp-servers link farm, npm-tarball builds for
  # browsermcp/gitnexus). The github MCP is the official local server; its
  # token is fetched per launch from the gh keyring by the
  # opencode-github-mcp wrapper and explicitly injected only into that
  # server's `env -i` environment. This prevents ambient inheritance, not
  # independent keyring access by another process running as the same user.
  #
  # No plugin is fetched from the npm registry at startup: native V2 plugins
  # come from ~/.config/opencode/plugins/ — env-protection.js is a repo file,
  # whisperopencode-push.js is the Nix-built, bundled plugin file.

  home.packages = [
    # Needed to provision and inspect the keyring credential consumed by the
    # absolute gh path inside opencode-github-mcp.
    pkgs.gh
    managedOpencode
    opencodePkgs.opencode-excalidraw-mcp
    opencodePkgs.opencode-github-mcp
    opencodePkgs.browsermcp
    opencodePkgs.gitnexus
    opencodePkgs.mcp-servers
  ];

  home.sessionPath = ["${managedOpencode}/bin"];
  home.sessionVariables.OPENCODE_DISABLE_AUTOUPDATE = "1";

  xdg.configFile = {
    # Main configuration. MCP commands are rendered with absolute store paths
    # from the readable source JSON above.
    "opencode/opencode.json".text = builtins.toJSON renderedConfig;

    # Plugins (auto-loaded by OpenCode from ~/.config/opencode/plugins/)
    "opencode/plugins/env-protection.js".source = opencodeDir + "/plugins/env-protection.js";
    "opencode/plugins/whisperopencode-push.js".source = "${whisperopencodePush}/whisperopencode-push.js";

    # MCP server — excalidraw: the prebuilt dist stays in the Nix store;
    # the wrapper resolves it from there (nothing is deployed under
    # ~/.config/opencode/mcp/).

    # Prompts
    "opencode/prompts/ai_engineer.txt".source = opencodeDir + "/prompts/ai_engineer.txt";
    "opencode/prompts/backend.txt".source = opencodeDir + "/prompts/backend.txt";
    "opencode/prompts/bug_hunter.txt".source = opencodeDir + "/prompts/bug_hunter.txt";
    "opencode/prompts/code_reviewer.txt".source = opencodeDir + "/prompts/code_reviewer.txt";
    "opencode/prompts/devops.txt".source = opencodeDir + "/prompts/devops.txt";
    "opencode/prompts/docs_writer.txt".source = opencodeDir + "/prompts/docs_writer.txt";
    "opencode/prompts/effectts.md".source = opencodeDir + "/prompts/effectts.md";
    "opencode/prompts/explore.txt".source = opencodeDir + "/prompts/explore.txt";
    "opencode/prompts/frontend.txt".source = opencodeDir + "/prompts/frontend.txt";
    "opencode/prompts/git.md".source = opencodeDir + "/prompts/git.md";
    "opencode/prompts/git.txt".source = opencodeDir + "/prompts/git.txt";
    "opencode/prompts/librarian.txt".source = opencodeDir + "/prompts/librarian.txt";
    "opencode/prompts/oracle.txt".source = opencodeDir + "/prompts/oracle.txt";
    "opencode/prompts/performance.txt".source = opencodeDir + "/prompts/performance.txt";
    "opencode/prompts/refactor.txt".source = opencodeDir + "/prompts/refactor.txt";
    "opencode/prompts/security.txt".source = opencodeDir + "/prompts/security.txt";
    "opencode/prompts/test_writer.txt".source = opencodeDir + "/prompts/test_writer.txt";

    # Skills
    "opencode/skills/gitnexus-cli/SKILL.md".source = opencodeDir + "/skills/gitnexus-cli/SKILL.md";
    "opencode/skills/gitnexus-debugging/SKILL.md".source = opencodeDir + "/skills/gitnexus-debugging/SKILL.md";
    "opencode/skills/gitnexus-exploring/SKILL.md".source = opencodeDir + "/skills/gitnexus-exploring/SKILL.md";
    "opencode/skills/gitnexus-guide/SKILL.md".source = opencodeDir + "/skills/gitnexus-guide/SKILL.md";
    "opencode/skills/gitnexus-impact-analysis/SKILL.md".source = opencodeDir + "/skills/gitnexus-impact-analysis/SKILL.md";
    "opencode/skills/gitnexus-refactoring/SKILL.md".source = opencodeDir + "/skills/gitnexus-refactoring/SKILL.md";
  };
}
