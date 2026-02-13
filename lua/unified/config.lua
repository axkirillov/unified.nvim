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
  file_tree = {
    width = 0.5, -- Width of the file tree window
    filename_first = true, -- Show filename before directory path (Snacks backend only)
  },
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

  -- Initialize namespace
  M.ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Define signs if not already defined
  if vim.fn.sign_getdefined("unified_diff_add")[1] == nil then
    vim.fn.sign_define("unified_diff_add", {
      text = M.values.line_symbols.add,
      texthl = M.values.highlights.add,
    })
  end

  if vim.fn.sign_getdefined("unified_diff_delete")[1] == nil then
    vim.fn.sign_define("unified_diff_delete", {
      text = M.values.line_symbols.delete,
      texthl = M.values.highlights.delete,
    })
  end

  if vim.fn.sign_getdefined("unified_diff_change")[1] == nil then
    vim.fn.sign_define("unified_diff_change", {
      text = M.values.line_symbols.change,
      texthl = M.values.highlights.change,
    })
  end
end

-- Get a specific config value
function M.get(name)
  return M.values[name]
end

return M
