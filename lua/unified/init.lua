local M = {}
local diff = require("unified.diff")
local git = require("unified.git") -- Restore require
local state = require("unified.state")
local file_tree = require("unified.file_tree") -- Restore require
local commit_module = require("unified.commit")

function M.setup(opts)
  local config = require("unified.config")
  local command = require("unified.command")
  config.setup(opts)
  command.setup()
end

-- Use parse_diff function from diff module
M.parse_diff = diff.parse_diff

-- Expose git functions directly for testing or specific use cases
M.show_git_diff = git.show_git_diff -- Restore assignment
M.show_git_diff_against_commit = git.show_git_diff_against_commit -- Restore assignment

-- Expose file tree functions
M.show_file_tree = file_tree.show_file_tree -- Restore assignment

-- Helper function to check if diff is displayed (for compatibility)
function M.is_diff_displayed(buffer)
  -- Check the global state first
  if state.is_active then
    return true
  end

  -- Also check the buffer as a fallback (for compatibility with older code)
  buffer = buffer or vim.api.nvim_get_current_buf()
  return diff.is_diff_displayed(buffer)
end

---@deprecated, use diff.show instead
function M.show_diff(commit)
  local buffer = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(buffer, "filetype")

  if ft == "unified_tree" then
    return false
  end

  local result

  if commit then
    state.set_commit_base(commit)
    result = git.show_git_diff_against_commit(commit)
  else
    local base = state.get_commit_base()
    result = git.show_git_diff_against_commit(base)
  end

  return result
end

-- Helper function to deactivate diff display
function M.deactivate()
  local buffer = vim.api.nvim_get_current_buf()
  local config = require("unified.config")
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
  local auto_refresh = require("unified.auto_refresh")
  local buffer = vim.api.nvim_get_current_buf()
  local config = require("unified.config")

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

  local commit_base = state.get_commit_base()
  local result = diff.show(commit_base)

  if result and config.values.auto_refresh then
    auto_refresh.setup()
  end

  if not state.opening_from_tree then
    file_tree.show_file_tree()
  end
  -- Update global state only if diff was successful
  if result then
    state.is_active = true
    vim.api.nvim_echo({ { "Unified diff activated", "Normal" } }, false, {})
  else
    vim.api.nvim_echo({ { "Failed to display diff, showing file tree only", "WarningMsg" } }, false, {})
  end
end

return M
