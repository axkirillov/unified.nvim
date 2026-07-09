-- State management for unified.nvim
local M = {}
local m = {
  commit_base = nil,
  active = false,
  backend = "default", -- "default" or "snacks"
}

-- Main window reference
M.main_win = nil

-- File tree window and buffer references
M.file_tree_win = nil
M.file_tree_buf = nil

-- Auto-refresh augroup ID
M.auto_refresh_augroup = nil

-- Flag to prevent recursive tree refresh when opening a file from the tree

-- Get the main content window (to navigate from tree back to content). Skips the
-- tree window and any window showing a non-file buffer (a terminal, help,
-- quickfix, ...): a file diff has no business replacing those. When unified is
-- launched from such a buffer there may be no content window yet -- returning nil
-- tells the caller (file_tree.actions) to create a real split instead.
--
-- The tree and its content window always live in a single tab page, so both the
-- cached fast-path and the fallback search are scoped to the *current* tab page.
-- nvim_list_wins() spans every tab; using it here let a file opened from a tree
-- in one tab leak into a window belonging to another tab (e.g. after `:tabnew`
-- then `:Unified`).
function M.get_main_window()
  local current_tab = vim.api.nvim_get_current_tabpage()

  local function in_current_tab(win)
    return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == current_tab
  end

  if
    M.main_win
    and in_current_tab(M.main_win)
    and (not M.file_tree_win or not vim.api.nvim_win_is_valid(M.file_tree_win) or M.main_win ~= M.file_tree_win)
  then
    return M.main_win
  end

  local valid_file_tree_win = M.file_tree_win and vim.api.nvim_win_is_valid(M.file_tree_win)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    local is_tree = valid_file_tree_win and win == M.file_tree_win
    if not is_tree and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
      M.main_win = win
      return win
    end
  end

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

function M.set_active(val)
  m.active = not not val
end
function M.is_active()
  return m.active
end

function M.set_backend(backend)
  m.backend = backend
end

function M.get_backend()
  return m.backend
end

return M
