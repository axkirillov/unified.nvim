-- Example configuration for unified.nvim

-- Default configuration
require("unified").setup({
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
