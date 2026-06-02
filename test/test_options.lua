-- Tests for configuration options: file_tree.enabled and file_tree.focus,
-- plus the reset/active-state contract that toggle() relies on.
local M = {}

local utils = require("test.test_utils")

-- Establish a clean baseline before each test: tear down any diff/tree left by a
-- previous test or group, drop stale window handles, and restore default config.
-- This module's tests assert on global tree state, so they can't inherit leakage.
local function clean_slate()
  pcall(require("unified.command").reset)
  local state = require("unified.state")
  state.file_tree_win = nil
  state.file_tree_buf = nil
  require("unified.config").setup({})
end

M.setup = clean_slate
M.teardown = clean_slate

-- Poll until `fn()` returns truthy or the timeout elapses.
local function wait_until(fn, timeout)
  timeout = timeout or 1000
  local start = vim.loop.hrtime()
  while vim.loop.hrtime() - start < timeout * 1e6 do
    if fn() then
      return true
    end
    vim.wait(20, function() end, 1, false)
  end
  return fn()
end

local function buffer_has_diff(buffer)
  return #vim.api.nvim_buf_get_extmarks(buffer, require("unified.config").ns_id, 0, -1, {}) > 0
end

local function open_modified_file(repo)
  local path = utils.create_and_commit_file(
    repo,
    "test.txt",
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )
  vim.cmd("edit " .. path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" })
  return path
end

local function any_tree_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "unified_tree" then
      return win
    end
  end
  return nil
end

-- The reset/active fix: closing the tree with `q` nils file_tree_win but leaves
-- the diff active. `reset` must still deactivate, otherwise toggle() gets stuck
-- always calling reset and can never turn the diff back on.
function M.test_reset_deactivates_when_tree_already_closed()
  local state = require("unified.state")
  state.set_active(true)
  state.set_commit_base("HEAD")
  -- Simulate the tree having been closed via `q`.
  state.file_tree_win = nil
  state.file_tree_buf = nil

  require("unified.command").reset()

  assert(not state.is_active(), "reset must set active=false even when the tree window is already closed")
  assert(state.get_backend() == "default", "reset must restore the default backend")
  return true
end

-- file_tree.enabled = false: :Unified shows the diff for the current buffer and
-- never opens a tree window.
function M.test_enabled_false_diffs_current_buffer_without_tree()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({ file_tree = { enabled = false } })

  open_modified_file(repo)
  local buffer = vim.api.nvim_get_current_buf()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "diff should be shown for the current buffer when the tree is disabled"
  )
  assert(any_tree_window() == nil, "no file tree window should be opened when enabled = false")
  assert(require("unified.state").file_tree_win == nil, "file_tree_win should remain unset when enabled = false")

  utils.cleanup_git_repo(repo)
  return true
end

-- Default (focus = false): the tree still opens, but focus stays in the current
-- buffer and that buffer's diff is shown in place.
function M.test_focus_false_keeps_focus_in_current_buffer()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({})

  open_modified_file(repo)
  local buffer = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "current buffer should show its diff"
  )
  -- The tree still opens by default (enabled = true); it just must not steal focus.
  assert(
    wait_until(function()
      return any_tree_window() ~= nil
    end),
    "tree should open by default"
  )
  assert(vim.api.nvim_get_current_win() == win, "focus should stay in the original window when focus = false")
  assert(vim.bo[vim.api.nvim_get_current_buf()].filetype ~= "unified_tree", "focus should not be in the tree window")

  utils.cleanup_git_repo(repo)
  return true
end

-- focus = true: the cursor moves into the tree on open, but the current buffer's
-- diff is still shown -- the diff follows your buffer, not the tree selection.
function M.test_focus_true_lands_in_tree_but_still_diffs_current()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({ file_tree = { focus = true } })

  open_modified_file(repo)
  local buffer = vim.api.nvim_get_current_buf()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "current buffer should be diffed even when focus jumps to the tree"
  )
  assert(
    wait_until(function()
      return vim.bo[vim.api.nvim_get_current_buf()].filetype == "unified_tree"
    end),
    "focus should move into the tree when focus = true"
  )

  utils.cleanup_git_repo(repo)
  return true
end

return M
