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
  -- When true, showing a diff moves the cursor to the first changed hunk: both
  -- when a file is opened from the tree and when :Unified runs on the current
  -- buffer. Set false to leave the cursor where it is.
  jump_to_first_hunk = true,
  -- When true, :Unified opens its diff view (the content window and the file
  -- tree) in a new tab, leaving your current window layout untouched. `:Unified
  -- -t` forces this for a single invocation regardless of this setting.
  tab = false,
  file_tree = {
    enabled = true, -- When false, :Unified never opens the file tree; the diff is shown for the current buffer.
    width = 30, -- Width of the file tree window (columns, or 0-1 for relative)
    filename_first = true, -- Show filename before directory path (Snacks backend only)
    -- When true, :Unified moves the cursor into the tree on open. When false, focus
    -- stays in your buffer. The current buffer's diff is shown either way.
    focus = false,
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
