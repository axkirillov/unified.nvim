local M = {}

-- Store window references (moved from init.lua)
M.main_win = nil
M.file_tree_win = nil
M.file_tree_buf = nil

-- Get the current commit base (now globally stored)
function M.get_window_commit_base()
  -- Get the global commit base from the unified module
  local unified = require("unified")
  return unified.global_commit_base or "HEAD"
end

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

-- Set the commit base globally
function M.set_window_commit_base(commit)
  local unified = require("unified")
  unified.global_commit_base = commit
end

return M
