-- Module for handling commit-related functionality in unified.nvim
local M = {}

-- Handle the "Unified <ref>" command
function M.handle_commit_command(commit_ref)
  local commit_hash = require("unified.git").resolve_commit_hash(commit_ref)

  -- Store a reference to main window if not already active
  local state = require("unified.state")
  if not state.is_active then
    state.main_win = vim.api.nvim_get_current_win()
  end

  -- Store the commit in global state, even if buffer has no name
  state.set_commit_base(commit_hash)

  local unified = require("unified")
  if unified.show_file_tree then
    unified.show_file_tree(commit_hash)
  end

  -- Focus the file tree window if it exists and is valid
  if state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win) then
    vim.api.nvim_set_current_win(state.file_tree_win)
  end

  -- Update global state - activate even if we can't show diff in current buffer
  state.is_active = true

  return true
end

return M
