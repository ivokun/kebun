local plugins = {
  {
    "mason-org/mason.nvim",
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = ":MasonUpdate",
    opts_extend = { "ensure_installed" },
    opts = {
      ensure_installed = {
        -- lua stuff
        "lua-language-server",
        "stylua",

        -- web dev stuff
        "css-lsp",
        "html-lsp",
        "typescript-language-server",
        "eslint-lsp",
        "eslint_d",
        "terraform-ls",
        "astro-language-server",
        "svelte-language-server",
        "prisma-language-server",
        "golangci-lint-langserver",
        "golangci-lint",
        "pyright",
        "python-lsp-server",
        "black",
        "ruff",
        "elixir-ls",
        "rust-analyzer",
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)
      local registry = require("mason-registry")
      registry.refresh(function()
        for _, tool in ipairs(opts.ensure_installed) do
          local p = registry.get_package(tool)
          if not p:is_installed() then
            p:install()
          end
        end
      end)
    end,
  },

  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
    },
  },

  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_refresh = 1
      vim.g.mkdp_refresh_slow = 1
      vim.g.mkdp_command_for_global = 0
      vim.g.mkdp_echo_preview_url = 1
      vim.g.mkdp_port = 7777
    end,
    ft = { "markdown" },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    init = function()
      -- Force compilation from source on NixOS (prebuilt binaries
      -- are linked for generic Linux and fail with stub-ld).
      require("nvim-treesitter.install").prefer_git = true
    end,
    opts = { ensure_installed = { "git_config", "gitcommit", "git_rebase", "gitignore", "gitattributes" } },
  },

  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
    config = function()
      vim.o.background = "light"
      vim.cmd("colorscheme rose-pine-dawn")
    end,
  },

  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local hostname = vim.fn.hostname()
      local header = hostname

      -- Try figlet for ASCII art (falls back to plain text if missing)
      local handle = io.popen("figlet -f slant " .. hostname .. " 2>/dev/null")
      if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result:match("%S") then
          header = result
        end
      end

      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.header = header
    end,
  },
}

return plugins
