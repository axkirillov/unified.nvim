-- Keybindings for unified_tree filetype

-- Set buffer options
vim.bo.modifiable = false
vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.bufhidden = "wipe"

-- Set mappings
local function set_keymap(mode, lhs, rhs, opts)
  local options = { noremap = true, silent = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.api.nvim_buf_set_keymap(0, mode, lhs, rhs, options)
end

-- Expand/collapse folder or open file
set_keymap("n", "<CR>", ":lua require('unified.file_tree').toggle_node()<CR>")

-- Close the tree
set_keymap("n", "q", ":q<CR>")

-- Refresh the tree
set_keymap("n", "R", ":lua require('unified.file_tree').refresh()<CR>")

-- Tree navigation
set_keymap("n", "j", "j")
set_keymap("n", "k", "k")
set_keymap("n", "h", ":lua require('unified.file_tree').collapse_node()<CR>")
set_keymap("n", "l", ":lua require('unified.file_tree').expand_node()<CR>")