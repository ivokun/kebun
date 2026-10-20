// Raises the shell tool's default foreground timeout. V2 hardcodes 2 minutes
// (core/src/tool/plugin/shell.ts) and no longer reads
// OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS, which kills routine
// `nix flake check` and VM-test runs mid-evaluation. Only calls that omit a
// timeout are changed: an explicit timeout (including 0 = none) and
// background commands keep upstream behavior.
const DEFAULT_TIMEOUT_MS = 10 * 60 * 1000

export default {
  id: "shell-timeout",

  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      if (event.tool !== "shell") return
      const input = event.input
      if (input === null || typeof input !== "object") return
      if (input.background === true || input.timeout !== undefined) return
      event.input = { ...input, timeout: DEFAULT_TIMEOUT_MS }
    })
  },
}
