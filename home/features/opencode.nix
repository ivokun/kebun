{
  config,
  lib,
  pkgs,
  ...
}: let
  opencodeDir = ../opencode;
in {
  # ─── Opencode configuration ───
  # Deploys opencode agent configs, prompts, skills, plugins, and MCP servers
  # to ~/.config/opencode/ via home-manager.
  #
  # NOTE: The GitHub MCP token in opencode.json is sanitized.
  # Set it manually after rebuild, or override via local config.

  xdg.configFile = {
    # Main configuration
    "opencode/opencode.json".source = opencodeDir + "/opencode.json";

    # Plugin
    "opencode/plugin/env-protection.js".source = opencodeDir + "/plugin/env-protection.js";

    # MCP server — excalidraw (pre-built dist)
    "opencode/mcp/excalidraw-mcp/dist/index.js".source = opencodeDir + "/mcp/excalidraw-mcp/dist/index.js";
    "opencode/mcp/excalidraw-mcp/dist/server.js".source = opencodeDir + "/mcp/excalidraw-mcp/dist/server.js";
    "opencode/mcp/excalidraw-mcp/dist/mcp-app.html".source = opencodeDir + "/mcp/excalidraw-mcp/dist/mcp-app.html";
    "opencode/mcp/excalidraw-mcp/dist/checkpoint-store.d.ts".source = opencodeDir + "/mcp/excalidraw-mcp/dist/checkpoint-store.d.ts";
    "opencode/mcp/excalidraw-mcp/dist/server.d.ts".source = opencodeDir + "/mcp/excalidraw-mcp/dist/server.d.ts";

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
