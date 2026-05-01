-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Memory watchdog
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  callback = function()
    local mem = collectgarbage("count") / 1024
    if mem > 2000 then
      -- Disable treesitter on large files / JSON
      vim.cmd("TSDisable highlight")
      vim.cmd("TSDisable indent")
      collectgarbage("collect")
    elseif mem > 1000 then
      vim.notify("Memory warning: " .. math.floor(mem) .. "MB", vim.log.levels.WARN)
    end
  end,
})

-- Force GC on buffer delete
vim.api.nvim_create_autocmd("BufDelete", {
  callback = function()
    collectgarbage("collect")
  end,
})
