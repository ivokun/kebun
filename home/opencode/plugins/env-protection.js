// Best-effort guard against accidentally using OpenCode's read tool on a
// dotenv file. This is not a sandbox: shell commands and same-uid processes
// can still read user-owned files, so secrets must not rely on this hook.
const isDotenvPath = (filePath) =>
  String(filePath ?? "")
    .split(/[\\/]/)
    .some((part) => part === ".env" || part.startsWith(".env."))

export default {
  id: "env-protection",

  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      const input = event.input ?? {}
      const filePath = input.path ?? input.filePath

      if (event.tool === "read" && isDotenvPath(filePath)) {
        throw new Error("Refusing to read dotenv files")
      }
    })
  },
}
