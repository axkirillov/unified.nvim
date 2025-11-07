-- Minimal Neovim init for unified.nvim tests

-- Keep startup deterministic
vim.g.mapleader = " "
vim.o.loadplugins = false
vim.o.swapfile = false
vim.o.writebackup = false
vim.o.backup = false
vim.o.undofile = false
vim.o.shortmess = vim.o.shortmess .. "I"

-- Stable UI for tests
vim.wo.signcolumn = "yes"

-- Ensure the plugin is on runtimepath via env
local plugin_dir = vim.env.UNIFIED_PLUGIN_DIR
if not plugin_dir or plugin_dir == "" then
  error("UNIFIED_PLUGIN_DIR not set (export UNIFIED_PLUGIN_DIR=<path to plugin root>)")
end
vim.opt.runtimepath:append(plugin_dir)

-- Optional coverage (off by default)
if vim.env.UNIFIED_COVERAGE == "1" then
  pcall(require, "luacov")
end

return true
