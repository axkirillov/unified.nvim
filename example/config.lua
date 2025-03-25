-- Example configuration for unified.nvim

-- Default configuration
require('unified').setup({
  -- Sign column symbols
  signs = {
    add = "│",
    delete = "│",
    change = "│",
  },
  -- Highlight groups
  highlights = {
    add = "DiffAdd",
    delete = "DiffDelete",
    change = "DiffChange",
  },
  -- Prefix symbols for inline virtual text
  line_symbols = {
    add = "+",
    delete = "-",
    change = "~",
  },
})

-- Example of custom key mappings
vim.keymap.set('n', '<leader>ud', ':UnifiedDiffToggle<CR>', { silent = true, desc = "Toggle unified diff" })
vim.keymap.set('n', '<leader>us', ':UnifiedDiffShow<CR>', { silent = true, desc = "Show unified diff" })