# Shared obsidian-multivault MCP definition for Claude Code and Claude Desktop.
#
# Both clients reuse the SSH argument list from home/opencode/opencode.json (the
# source of truth) instead of duplicating identity files, keepalives, host-key
# policy, or the pinned remote entry point. Claude Code uses Home Manager's
# native programs.claude-code module, which writes the global personal plugin
# ~/.claude/skills/claude-code-home-manager and adds `type = "stdio"` itself.
# `package = null` keeps the repo's pinned claude-code from home/common.nix as
# the only binary and leaves ~/.claude.json / ~/.claude/settings.json app-owned.
#
# Claude Desktop has no Home Manager module, so its mutable
# ~/.config/Claude/claude_desktop_config.json is never HM-owned or read at
# evaluation time. Activation merges only the desired MCP entry using
# packages/claude-desktop/merge-mcp-config.py, which preserves unrelated keys
# and servers, is idempotent, and keeps a one-time 0600 backup of the original.
{
  config,
  lib,
  pkgs,
  ...
}: let
  opencodeConfig = builtins.fromJSON (builtins.readFile ../opencode/opencode.json);
  sourceCommand = opencodeConfig.mcp.servers."obsidian-multivault".command;

  claudeServer = {
    command = "${pkgs.openssh}/bin/ssh";
    args = builtins.tail sourceCommand;
  };

  desktopMcpConfig = pkgs.writeText "claude-desktop-mcp.json" (builtins.toJSON {
    mcpServers = {
      "obsidian-multivault" = claudeServer;
    };
  });
in
  assert lib.assertMsg (
    builtins.length sourceCommand > 1 && builtins.head sourceCommand == "ssh"
  ) "claude-mcp.nix: the obsidian-multivault source command must start with ssh"; {
    programs.claude-code = {
      enable = true;
      # Keep the repo's claude-code package as the only binary; the module only
      # manages the personal plugin that carries this MCP server.
      package = null;
      mcpServers."obsidian-multivault" = claudeServer;
    };

    # Keep the app-owned config outside HM's managed file tree. Mutations run
    # after writeBoundary; `run` makes dry runs safe, and malformed configs
    # warn without blocking unrelated activation steps.
    home.activation.claudeDesktopMcp = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if ! run ${pkgs.python3}/bin/python3 ${../../packages/claude-desktop/merge-mcp-config.py} ${lib.escapeShellArg "${config.xdg.configHome}/Claude/claude_desktop_config.json"} ${desktopMcpConfig}; then
        warnEcho "Claude Desktop MCP configuration was not updated; quit the app, fix the reported configuration issue, and rebuild."
      fi
    '';
  }
