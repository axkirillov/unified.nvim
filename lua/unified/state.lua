-- State management for unified.nvim
local M = {}
local m = {
  commit_base = nil,
}

-- Global state for the plugin
M.is_active = false

-- Main window reference
M.main_win = nil

-- File tree window and buffer references
M.file_tree_win = nil
M.file_tree_buf = nil

-- Auto-refresh augroup ID
M.auto_refresh_augroup = nil

-- Flag to prevent recursive tree refresh when opening a file from the tree

-- Get the main content window (to navigate from tree back to content)
function M.get_main_window()
  if
    M.main_win
    and vim.api.nvim_win_is_valid(M.main_win)
    and (not M.file_tree_win or not vim.api.nvim_win_is_valid(M.file_tree_win) or M.main_win ~= M.file_tree_win)
  then
    return M.main_win
  end

  local valid_file_tree_win = M.file_tree_win and vim.api.nvim_win_is_valid(M.file_tree_win)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not valid_file_tree_win or win ~= M.file_tree_win then
      M.main_win = win
      return win
    end
  end

  vim.api.nvim_err_writeln("Unified: Could not find a suitable main window.")
  return nil
end

function M.set_commit_base(commit)
  m.commit_base = commit
  vim.api.nvim_exec_autocmds("User", { pattern = "UnifiedBaseCommitUpdated" })
end

---@return string
function M.get_commit_base()
  if m.commit_base == nil then
    error("Commit base is not set")
  end
  return m.commit_base
end

return M
