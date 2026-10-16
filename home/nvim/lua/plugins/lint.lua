return {
  -- Formatter configuration
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    opts = {
      formatters_by_ft = {
        vue = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        less = { "prettier" },
        html = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        ["markdown.mdx"] = { "prettier" },
        graphql = { "prettier" },
        handlebars = { "prettier" },
        astro = { "prettier" },
        lua = { "stylua" },
        sh = { "shfmt" },
        cpp = { "clang_format" },
        c = { "clang_format" },
        rust = { "rustfmt" },
        go = { "gofmt" },
        python = { "black" },
        terraform = { "terraform_fmt" },
        typescript = { "biome" },
        typescriptreact = { "biome" },
        javascript = { "biome" },
        javascriptreact = { "biome" },
        -- Add more as needed
      },
      formatters = {
        biome = {
          require_cwd = true,
          args = { "format", "--write", "--stdin-file-path", "$FILENAME" },
        },
      },
      format_on_save = true,
      notify_on_error = true,
    },
  },
  -- Linter configuration. Only linters_by_ft is set here: LazyVim's own
  -- nvim-lint config merges it and lints on BufWritePost/BufReadPost/InsertLeave
  -- with a debounce. The old custom config() re-linted on every BufEnter and
  -- silently dropped opts.linters; the shellcheck "--format gcc" override it
  -- carried would also break nvim-lint's json1 parser if it were ever applied.
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        sh = { "shellcheck" },
        go = { "golangci_lint" },
        python = { "ruff" },
      },
    },
  },
}
