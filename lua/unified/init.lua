local M = {}

function M.setup(opts)
  local config = require("unified.config")
  local command = require("unified.command")
  local file_tree = require("unified.file_tree")
  config.setup(opts)
  command.setup()
  file_tree.setup()
end

---@deprecated, use diff.show instead
function M.show_diff(commit)
  local buffer = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(buffer, "filetype")

  if ft == "unified_tree" then
    return false
  end

  local result

  local git = require("unified.git")
  local state = require("unified.state")
  if commit then
    state.set_commit_base(commit)
    result = git.show_git_diff_against_commit(commit)
  else
    local base = state.get_commit_base()
    result = git.show_git_diff_against_commit(base)
  end

  return result
end

---@deprecated
function M.activate()
  local auto_refresh = require("unified.auto_refresh")
  local buffer = vim.api.nvim_get_current_buf()
  local config = require("unified.config")

  -- Store current window as main window
  local state = require("unified.state")
  state.main_win = vim.api.nvim_get_current_win()

  -- Get buffer name
  local filename = vim.api.nvim_buf_get_name(buffer)

  -- Check if buffer has a name
  if filename == "" then
    -- It's an empty buffer with no name, just show file tree without diff
    local file_tree = require("unified.file_tree")
    file_tree.show_file_tree(vim.fn.getcwd()) -- Restore original call
    vim.api.nvim_echo({ { "Showing file tree for current directory", "Normal" } }, false, {})
    return
  end

  local commit_base = state.get_commit_base()
  local diff = require("unified.diff")
  local result = diff.show(commit_base)

  if result and config.values.auto_refresh then
    auto_refresh.setup()
  end

  if not state.opening_from_tree then
    local file_tree = require("unified.file_tree")
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
