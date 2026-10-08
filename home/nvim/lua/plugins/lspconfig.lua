return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      biome = {},
      -- installed by Nix (extraPackages), not Mason — see plugins.lua
      lua_ls = { mason = false },
      html = {},
      cssls = {},
      ts_ls = {},
      clangd = {},
      terraformls = {},
      astro = {},
      eslint = {},
      golangci_lint_ls = {},
      pyright = {},
      elixirls = {},
      rust_analyzer = { mason = false },
    },
  },
}
