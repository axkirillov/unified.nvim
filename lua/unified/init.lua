local M = {}
local config = require("unified.config")
local diff_module = require("unified.diff")
local git = require("unified.git")
local window = require("unified.window")
local file_tree = require("unified.file_tree")

-- Setup function to be called by the user
function M.setup(opts)
  config.setup(opts)

  -- Use namespace from config
  M.ns_id = config.ns_id
end

-- Use parse_diff function from diff module
M.parse_diff = diff_module.parse_diff

-- Expose git functions directly for testing or specific use cases
M.show_git_diff = git.show_git_diff
M.show_git_diff_against_commit = git.show_git_diff_against_commit

-- Set up auto-refresh for current buffer
function M.setup_auto_refresh(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()

  -- Only set up if auto-refresh is enabled
  if not config.values.auto_refresh then
    return
  end

  -- Remove existing autocommand group if it exists
  if M.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(M.auto_refresh_augroup)
  end

  -- Create a unique autocommand group for this buffer
  M.auto_refresh_augroup = vim.api.nvim_create_augroup("UnifiedDiffAutoRefresh", { clear = true })

  -- Set up autocommand to refresh diff on text change
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = M.auto_refresh_augroup,
    buffer = buffer,
    callback = function()
      -- Only refresh if diff is currently displayed
      if diff_module.is_diff_displayed(buffer) then -- Use diff_module
        -- Use the stored window commit base for refresh
        M.show_diff() -- Call M.show_diff in this module
      end
    end,
  })
end

-- Show diff (always use git diff)
function M.show_diff(commit)
  local result

  if commit then
    -- Store the commit reference in the window
    window.set_window_commit_base(commit) -- Use window module
    result = git.show_git_diff_against_commit(commit) -- Use git module
  else
    -- Use stored commit base or default to HEAD
    local base = window.get_window_commit_base() -- Use window module
    result = git.show_git_diff_against_commit(base) -- Use git module
  end

  -- If diff was successfully displayed, set up auto-refresh
  if result and config.values.auto_refresh then
    M.setup_auto_refresh() -- Call M.setup_auto_refresh in this module
  end

  return result
end

-- Toggle diff display
function M.toggle_diff()
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = config.ns_id

  -- Check if diff is already displayed
  if diff_module.is_diff_displayed(buffer) then -- Use diff_module
    -- Clear diff display
    vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
    vim.fn.sign_unplace("unified_diff", { buffer = buffer })

    -- Remove auto-refresh autocmd if it exists
    if M.auto_refresh_augroup then
      vim.api.nvim_del_augroup_by_id(M.auto_refresh_augroup)
      M.auto_refresh_augroup = nil
    end

    -- Close file tree window if it exists
    if window.file_tree_win and vim.api.nvim_win_is_valid(window.file_tree_win) then -- Use window module
      vim.api.nvim_win_close(window.file_tree_win, true) -- Use window module
      window.file_tree_win = nil -- Use window module
      window.file_tree_buf = nil -- Use window module
    end

    -- Clear main window reference
    window.main_win = nil -- Use window module

    vim.api.nvim_echo({ { "Diff display cleared", "Normal" } }, false, {})
  else
    -- Store current window as main window
    window.main_win = vim.api.nvim_get_current_win() -- Use window module

    -- Get buffer name
    local filename = vim.api.nvim_buf_get_name(buffer)

    -- Check if buffer has a name
    if filename == "" then
      -- It's an empty buffer with no name, just show file tree without diff
      file_tree.show_file_tree(vim.fn.getcwd()) -- Use file_tree module
      vim.api.nvim_echo({ { "Showing file tree for current directory", "Normal" } }, false, {})
      return
    end

    -- Show diff based on the stored commit base (or default to HEAD)
    local result = M.show_diff() -- Call M.show_diff in this module

    -- Always show file tree, even if diff fails
    file_tree.show_file_tree() -- Use file_tree module

    if not result then
      vim.api.nvim_echo({ { "Failed to display diff, showing file tree only", "WarningMsg" } }, false, {})
    end
  end
end

return M
