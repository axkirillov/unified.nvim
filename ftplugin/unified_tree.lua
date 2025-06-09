vim.bo.modifiable = false
vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.bufhidden = "wipe"
vim.bo.syntax = "unified_tree"

vim.wo.cursorline = true
vim.wo.statusline = "File Explorer"
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.winfixwidth = true
vim.wo.foldenable = false
vim.wo.list = false
vim.wo.wrap = false

vim.keymap.set("n", "j",
  function()
    require('unified.file_tree.actions').move_cursor_and_open_file(1)
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "k",
  function()
    require('unified.file_tree.actions').move_cursor_and_open_file(-1)
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "R",
  function()
    require('unified.file_tree.actions').refresh()
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "q",
  function()
    require('unified.file_tree.actions').close_tree()
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "?",
  function()
    require('unified.file_tree.actions').show_help()
  end,
  { noremap = true, silent = true, buffer = true }
)
