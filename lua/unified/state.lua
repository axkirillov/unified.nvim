-- State management for unified.nvim
local M = {}

-- Global state for the plugin
M.is_active = false

-- Global commit base that persists across buffers
M.commit_base = "HEAD"

-- Main window reference
M.main_win = nil

-- File tree window and buffer references
M.file_tree_win = nil
M.file_tree_buf = nil

-- Auto-refresh augroup ID
M.auto_refresh_augroup = nil

-- Flag to prevent recursive tree refresh when opening a file from the tree
M.opening_from_tree = false

-- Get the main content window (to navigate from tree back to content)
function M.get_main_window()
  -- If we have stored a main window and it's valid, use it
  if M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
    return M.main_win
  end

  -- Otherwise find the first window that's not our tree window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not M.file_tree_win or win ~= M.file_tree_win then
      -- Store this as our main window
      M.main_win = win
      return win
    end
  end

  -- Fallback to current window
  return vim.api.nvim_get_current_win()
end

-- Set the commit base
function M.set_commit_base(commit)
  M.commit_base = commit
  vim.api.nvim_exec_autocmds("User", { pattern = "UnifiedBaseCommitUpdated" })
end

-- Get the current commit base
function M.get_commit_base()
  return M.commit_base or "HEAD"
end

return M
