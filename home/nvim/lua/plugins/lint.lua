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
  -- Linter configuration
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      linters_by_ft = {
        sh = { "shellcheck" },
        go = { "golangci_lint" },
        python = { "ruff" },
        -- Add more linters as desired for your filetypes
      },
      -- Optional on-attach for format/lint on save:
      linters = {
        shellcheck = { args = { "--format", "gcc" } }, -- Match diagnostics_format = "#{m} [#{c}]"
      },
    },
    config = function(_, opts)
      require("lint").linters_by_ft = opts.linters_by_ft
      -- Lint on save / after write
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter" }, {
        callback = function()
          require("lint").try_lint()
        end,
      })
    end,
  },
}
