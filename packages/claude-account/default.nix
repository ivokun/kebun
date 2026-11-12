# `claude` — route a bare invocation through Omarchy's active subscription
# account.
#
# Upstream Omarchy installs Claude Code through mise, whose shim calls
# omarchy-agent-account-exec, so a bare `claude` follows `omarchy agent account
# use`. Kebun installs the CLI from nixpkgs instead, so without this wrapper a
# bare `claude` always uses ~/.claude (Main), even when another account is
# active.
#
# Mirrors omarchy-agent-account-exec: an explicit CLAUDE_CONFIG_DIR wins; an
# OMARCHY_AGENT_CLAUDE_HOME pin (a running session) wins over the registry;
# otherwise the registry's active account decides. Main's home is empty, so
# CLAUDE_CONFIG_DIR stays unset and Claude keeps its ~/.claude.json default.
{
  writeShellScriptBin,
  omarchy,
  claude-code,
}:
writeShellScriptBin "claude" ''
  if [[ -z ''${CLAUDE_CONFIG_DIR:-} ]]; then
    account_home=$(PATH="${omarchy}/bin:''${PATH:-}" omarchy-agent-account-home claude 2>/dev/null) || account_home=""
    # The helper prints nothing for Main and otherwise only a home path.
    case $account_home in
      /*) ;;
      *) account_home="" ;;
    esac
    export OMARCHY_AGENT_CLAUDE_HOME="$account_home"
    [[ -n $account_home ]] && export CLAUDE_CONFIG_DIR="$account_home"
  fi
  exec ${claude-code}/bin/claude "$@"
''
