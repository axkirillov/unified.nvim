local M = {}

-- Configuration with default values
M.defaults = {
  signs = {
    add = "│",
    delete = "│",
    change = "│",
  },
  highlights = {
    add = "DiffAdd",
    delete = "DiffDelete",
    change = "DiffChange",
  },
  line_symbols = {
    add = "+",
    delete = "-",
    change = "~",
  },
  auto_refresh = true, -- Whether to auto-refresh diff when buffer changes
}

-- User configuration (will be populated in setup)
M.user = {}

-- Actual config that combines defaults with user config
M.values = vim.deepcopy(M.defaults)

-- Setup function to be called by the user
function M.setup(opts)
  -- Store user configuration
  M.user = vim.tbl_deep_extend("force", {}, opts or {})

  -- Update values with user config
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), M.user)

  -- Create highlights based on config
  vim.cmd("highlight default link UnifiedDiffAdd " .. M.values.highlights.add)
  vim.cmd("highlight default link UnifiedDiffDelete " .. M.values.highlights.delete)
  vim.cmd("highlight default link UnifiedDiffChange " .. M.values.highlights.change)
end

-- Get a specific config value
function M.get(name)
  return M.values[name]
end

return M
