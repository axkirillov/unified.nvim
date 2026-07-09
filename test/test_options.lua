-- Tests for configuration options: file_tree.enabled, file_tree.focus and
-- jump_to_first_hunk, plus the reset/active-state contract that toggle() relies on.
local M = {}

local utils = require("test.test_utils")

-- Establish a clean baseline before each test: tear down any diff/tree left by a
-- previous test or group, drop stale window handles, and restore default config.
-- This module's tests assert on global tree state, so they can't inherit leakage.
local function clean_slate()
  pcall(require("unified.command").reset)
  -- Collapse back to a single tab: the tab-aware tests below open extra tabs, and
  -- a leftover tab would skew the next test's window/tab assertions.
  pcall(vim.cmd, "tabonly")
  local state = require("unified.state")
  state.file_tree_win = nil
  state.file_tree_buf = nil
  state.main_win = nil
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

-- Open a file whose only change sits well below the top, with the cursor parked
-- at line 1. Lets a test observe whether :Unified jumps the cursor to the hunk.
local function open_file_with_late_hunk(repo)
  local lines = {}
  for i = 1, 10 do
    lines[i] = "line " .. i
  end
  local path = utils.create_and_commit_file(repo, "test.txt", lines, "Initial commit")
  vim.cmd("edit " .. path)
  vim.api.nvim_buf_set_lines(0, 6, 7, false, { "modified line 7" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
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

-- jump_to_first_hunk = true (default): :Unified on the current buffer lands the
-- cursor on the first changed hunk, even though the change is below the top.
function M.test_jump_to_first_hunk_moves_cursor_in_current_buffer()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({})

  open_file_with_late_hunk(repo)
  local buffer = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "current buffer should show its diff"
  )

  local first = require("unified.hunk_store").get(buffer)[1]
  assert(first and first > 1, "test setup: the first hunk should be below the top of the file")
  assert(
    vim.api.nvim_win_get_cursor(win)[1] == first,
    "cursor should jump to the first hunk line when jump_to_first_hunk is enabled"
  )

  utils.cleanup_git_repo(repo)
  return true
end

-- jump_to_first_hunk = false: the diff is shown but the cursor stays where it was.
function M.test_jump_to_first_hunk_false_keeps_cursor()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({ jump_to_first_hunk = false })

  open_file_with_late_hunk(repo)
  local buffer = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "diff should still be shown when jump_to_first_hunk is disabled"
  )

  local first = require("unified.hunk_store").get(buffer)[1]
  assert(first and first > 1, "test setup: the first hunk should be below the top of the file")
  assert(vim.api.nvim_win_get_cursor(win)[1] == 1, "cursor should stay put when jump_to_first_hunk is disabled")

  utils.cleanup_git_repo(repo)
  return true
end

-- Regression: opening a file from the tree must never leak into another tab.
-- get_main_window used to scan every window across all tabs (nvim_list_wins), so
-- with the tree in a fresh tab it could return a window in the original tab and
-- open the file there. It must only ever return a window in the current tab.
function M.test_get_main_window_scoped_to_current_tab()
  local state = require("unified.state")

  -- Original tab: a normal (buftype "") window that must be left untouched.
  vim.cmd("tabonly")
  vim.cmd("enew")
  local original_tab = vim.api.nvim_get_current_tabpage()
  local original_win = vim.api.nvim_get_current_win()

  -- New tab: a content window plus a fake tree window on the left, mimicking the
  -- layout after `:tabnew` then `:Unified`.
  vim.cmd("tabnew")
  local current_tab = vim.api.nvim_get_current_tabpage()
  local content_win = vim.api.nvim_get_current_win()
  vim.cmd("topleft vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  local tree_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tree_buf].filetype = "unified_tree"
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  state.file_tree_win = tree_win
  state.main_win = nil -- as when :Unified is launched from a non-file buffer

  -- Files are opened while the tree window is focused.
  vim.api.nvim_set_current_win(tree_win)
  local win = state.get_main_window()

  assert(win ~= nil, "a content window should be found in the current tab")
  assert(win ~= tree_win, "the tree window must never be chosen as the content window")
  assert(win ~= original_win, "must not reuse a window from the original tab")
  assert(
    vim.api.nvim_win_get_tabpage(win) == current_tab,
    "the content window must belong to the current tab, not tab " .. tostring(original_tab)
  )
  assert(win == content_win, "should reuse the content window that lives in the current tab")

  return true
end

-- tab = true: :Unified opens the diff view in a new tab, roots the content window
-- and the tree there, and leaves the original tab's window untouched.
function M.test_tab_option_opens_view_in_new_tab()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({ tab = true })

  vim.cmd("tabonly")
  open_modified_file(repo)
  local buffer = vim.api.nvim_get_current_buf()
  local original_tab = vim.api.nvim_get_current_tabpage()
  local original_win = vim.api.nvim_get_current_win()
  local tabs_before = #vim.api.nvim_list_tabpages()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "the diff should be shown"
  )
  assert(#vim.api.nvim_list_tabpages() == tabs_before + 1, "a new tab should be opened")

  local current_tab = vim.api.nvim_get_current_tabpage()
  assert(current_tab ~= original_tab, "focus should move to the new tab")

  local state = require("unified.state")
  assert(
    state.main_win and vim.api.nvim_win_get_tabpage(state.main_win) == current_tab,
    "the content window should live in the new tab"
  )
  assert(
    wait_until(function()
      return any_tree_window() ~= nil
    end),
    "the tree should open"
  )
  assert(vim.api.nvim_win_get_tabpage(any_tree_window()) == current_tab, "the tree should open in the new tab")

  -- The original tab is left as it was: a single window, and not the tree.
  assert(vim.api.nvim_win_is_valid(original_win), "the original window should still exist")
  assert(#vim.api.nvim_tabpage_list_wins(original_tab) == 1, "the original tab should keep its single window")

  utils.cleanup_git_repo(repo)
  return true
end

-- :Unified -t opens in a new tab for that invocation even when tab = false.
function M.test_tab_flag_opens_view_in_new_tab()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({}) -- tab defaults to false

  vim.cmd("tabonly")
  open_modified_file(repo)
  local buffer = vim.api.nvim_get_current_buf()
  local original_tab = vim.api.nvim_get_current_tabpage()
  local tabs_before = #vim.api.nvim_list_tabpages()

  require("unified.command").run("-t HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "the diff should be shown"
  )
  assert(#vim.api.nvim_list_tabpages() == tabs_before + 1, "-t should open a new tab")
  assert(vim.api.nvim_get_current_tabpage() ~= original_tab, "-t should move focus to the new tab")

  utils.cleanup_git_repo(repo)
  return true
end

-- Default (tab = false, no flag): :Unified stays in the current tab.
function M.test_default_stays_in_current_tab()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({})

  vim.cmd("tabonly")
  open_modified_file(repo)
  local buffer = vim.api.nvim_get_current_buf()
  local original_tab = vim.api.nvim_get_current_tabpage()
  local tabs_before = #vim.api.nvim_list_tabpages()

  require("unified.command").run("HEAD")

  assert(
    wait_until(function()
      return buffer_has_diff(buffer)
    end),
    "the diff should be shown"
  )
  assert(#vim.api.nvim_list_tabpages() == tabs_before, "no new tab should be opened by default")
  assert(vim.api.nvim_get_current_tabpage() == original_tab, "focus should stay in the current tab")

  utils.cleanup_git_repo(repo)
  return true
end

return M
