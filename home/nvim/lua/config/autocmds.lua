-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Memory watchdog. Measures the whole process (RSS), not just the Lua heap:
-- collectgarbage("count") only sees Lua objects, while runaway memory lives in
-- native allocations (treesitter trees, buffers, undo, queued events). Uses
-- vim.treesitter.stop() because nvim-treesitter's main branch has no :TSDisable.
local mem_warned = false
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("kebun_mem_watchdog", { clear = true }),
  callback = function(ev)
    local rss_mb = math.floor(vim.uv.resident_set_memory() / 1024 / 1024)
    if rss_mb < 4096 then
      mem_warned = false
      return
    end
    pcall(vim.treesitter.stop, ev.buf)
    collectgarbage("collect")
    if not mem_warned then
      mem_warned = true
      vim.notify(
        ("nvim RSS is %d MB; stopped treesitter for this buffer"):format(rss_mb),
        vim.log.levels.WARN
      )
    end
  end,
})

-- Force GC on buffer delete
vim.api.nvim_create_autocmd("BufDelete", {
  callback = function()
    collectgarbage("collect")
  end,
})
