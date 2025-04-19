-- Keybindings for unified_tree filetype

-- Set buffer options
vim.bo.modifiable = false
vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.bufhidden = "wipe"
vim.bo.syntax = "unified_tree"
vim.wo.cursorline = true
vim.wo.statusline = "File Explorer"

-- Set mappings
local function set_keymap(mode, lhs, rhs, opts)
  local options = { noremap = true, silent = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.api.nvim_buf_set_keymap(0, mode, lhs, rhs, options)
end

-- Close the tree
set_keymap("n", "q", ":q<CR>")

-- Refresh the tree
set_keymap("n", "R", ":lua require('unified.file_tree').refresh()<CR>")


-- Help dialog
set_keymap("n", "?", ":lua require('unified.file_tree').show_help()<CR>")
