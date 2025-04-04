local M = {}
local config = require("unified.config")
local diff_module = require("unified.diff") -- Restore require
local git = require("unified.git") -- Restore require
local state = require("unified.state")
local file_tree = require("unified.file_tree") -- Restore require
local commit = require("unified.commit")

-- Setup function to be called by the user
function M.setup(opts)
  config.setup(opts)

  -- Use namespace from config
  M.ns_id = config.ns_id
end

-- Use parse_diff function from diff module
M.parse_diff = diff_module.parse_diff -- Restore assignment

-- Expose git functions directly for testing or specific use cases
M.show_git_diff = git.show_git_diff -- Restore assignment
M.show_git_diff_against_commit = git.show_git_diff_against_commit -- Restore assignment

-- Expose file tree functions
M.show_file_tree = file_tree.show_file_tree -- Restore assignment

-- Expose commit functions
M.handle_commit_command = commit.handle_commit_command

-- No longer need to set functions on commit module

-- Helper function to check if diff is displayed (for compatibility)
function M.is_diff_displayed(buffer)
  -- Check the global state first
  if state.is_active then
    return true
  end

  -- Also check the buffer as a fallback (for compatibility with older code)
  buffer = buffer or vim.api.nvim_get_current_buf()
  return diff_module.is_diff_displayed(buffer) -- Restore original call
end

-- Set up auto-refresh for current buffer
function M.setup_auto_refresh(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()

  -- Only set up if auto-refresh is enabled
  if not config.values.auto_refresh then
    return
  end

  -- Remove existing autocommand group if it exists
  if state.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(state.auto_refresh_augroup)
  end

  -- Create a unique autocommand group for this buffer
  state.auto_refresh_augroup = vim.api.nvim_create_augroup("UnifiedDiffAutoRefresh", { clear = true })

  -- Set up autocommand to refresh diff on text change
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = state.auto_refresh_augroup,
    buffer = buffer,
    callback = function()
      -- Only refresh if diff is currently displayed
      if diff_module.is_diff_displayed(buffer) then -- Restore original call
        -- Use the stored commit base for refresh
        M.show_diff()
      end
    end,
  })
end

-- Show diff (always use git diff)
function M.show_diff(commit)
  local buffer = vim.api.nvim_get_current_buf() -- Get current buffer
  local ft = vim.api.nvim_buf_get_option(buffer, "filetype") -- Get filetype

  -- Prevent diffing the file tree buffer
  if ft == "unified_tree" then
    -- vim.api.nvim_echo({ { "Skipping diff for file tree buffer", "Comment" } }, false, {}) -- Optional debug
    return false -- Indicate diff was not shown
  end

  local result

  if commit then
    -- Store the commit reference globally
    state.set_commit_base(commit)
    result = git.show_git_diff_against_commit(commit) -- Restore original call
  else
    -- Use stored global commit base or default to HEAD
    local base = state.get_commit_base()
    result = git.show_git_diff_against_commit(base) -- Restore original call
  end

  -- If diff was successfully displayed, set up auto-refresh
  if result and config.values.auto_refresh then
    M.setup_auto_refresh()
  end

  return result
end

-- Helper function to deactivate diff display
function M.deactivate()
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = config.ns_id

  -- Clear diff display
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  -- Remove auto-refresh autocmd if it exists
  if state.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  -- Close file tree window if it exists and is not the last window
  if state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win) then
    -- Check if it's the last window
    local windows = vim.api.nvim_list_wins()
    if #windows > 1 then
      vim.api.nvim_win_close(state.file_tree_win, true)
    else
      -- If it's the last window, maybe just clear the buffer instead?
      -- Or rely on Neovim closing gracefully later. For now, just don't close.
      print("DEBUG: Skipping close of last window (file tree)")
    end
    -- Reset state even if window wasn't closed
    state.file_tree_win = nil
    state.file_tree_buf = nil
  end

  -- Clear main window reference
  state.main_win = nil

  -- Update global state
  state.is_active = false

  vim.api.nvim_echo({ { "Unified diff deactivated", "Normal" } }, false, {})
end

-- Helper function to activate diff display
function M.activate()
  local buffer = vim.api.nvim_get_current_buf()

  -- Store current window as main window
  state.main_win = vim.api.nvim_get_current_win()

  -- Get buffer name
  local filename = vim.api.nvim_buf_get_name(buffer)

  -- Check if buffer has a name
  if filename == "" then
    -- It's an empty buffer with no name, just show file tree without diff
    file_tree.show_file_tree(vim.fn.getcwd()) -- Restore original call
    vim.api.nvim_echo({ { "Showing file tree for current directory", "Normal" } }, false, {})
    return
  end

  -- Show diff based on the stored commit base (or default to HEAD)
  local result = M.show_diff()

  -- Always show file tree, even if diff fails
  file_tree.show_file_tree() -- Restore original call

  -- Update global state only if diff was successful
  if result then
    state.is_active = true
    vim.api.nvim_echo({ { "Unified diff activated", "Normal" } }, false, {})
  else
    vim.api.nvim_echo({ { "Failed to display diff, showing file tree only", "WarningMsg" } }, false, {})
  end
end

-- Toggle diff display based on global state
function M.toggle_diff()
  if state.is_active then
    M.deactivate()
  else
    M.activate()
  end
end
-- Comment out the deferred initialization to avoid potential load cycle

return M
