-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = false
vim.o.background = "light"

-- Silence the "harmless" ESLint warning
local notify = vim.notify
vim.notify = function(msg, ...)
  if msg:match("eslint triggers a registerCapability handler") then
    return
  end
  notify(msg, ...)
end
