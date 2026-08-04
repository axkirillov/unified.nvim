-- Tests for the commit picker: bare `:Unified` (no args) lists recent commits
-- via vim.ui.select and diffs the current buffer against the chosen one.
local M = {}

local utils = require("test.test_utils")

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

-- git.list_commits returns the history newest-first, each entry carrying a hash.
function M.test_list_commits_returns_history_newest_first()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  utils.create_and_commit_file(repo, "a.txt", { "a" }, "first change")
  utils.create_and_commit_file(repo, "b.txt", { "b" }, "second change")

  local result
  require("unified.git").list_commits(repo.repo_dir, 100, function(commits)
    result = commits or false
  end)

  assert(
    wait_until(function()
      return result ~= nil
    end),
    "list_commits should invoke its callback"
  )
  assert(result, "list_commits should return commits in a repo with history")
  assert(#result >= 2, "expected at least two commits, got " .. tostring(#result))
  assert(result[1].subject == "second change", "newest commit should be listed first")
  assert(result[1].hash and #result[1].hash > 0, "each commit should carry a hash")

  utils.cleanup_git_repo(repo)
  return true
end

-- An initialized repository without commits has no history to offer.
function M.test_list_commits_returns_nil_for_empty_history()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  local called = false
  local result
  require("unified.git").list_commits(repo.repo_dir, 100, function(commits)
    called = true
    result = commits
  end)

  assert(
    wait_until(function()
      return called
    end),
    "list_commits should invoke its callback for an empty repository"
  )
  assert(result == nil, "an empty repository should not return any commits")

  utils.cleanup_git_repo(repo)
  return true
end

-- The picker reports a useful warning instead of opening outside a git repository.
function M.test_picker_warns_outside_git_repository()
  local outside = vim.fn.tempname()
  vim.fn.mkdir(outside, "p")
  local old_dir = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(outside))

  local orig_echo = vim.api.nvim_echo
  local orig_select = vim.ui.select
  local message
  local selected = false
  vim.api.nvim_echo = function(chunks)
    message = chunks[1][1]
  end
  vim.ui.select = function()
    selected = true
  end

  require("unified.commit_picker").pick()

  vim.api.nvim_echo = orig_echo
  vim.ui.select = orig_select
  vim.cmd("lcd " .. vim.fn.fnameescape(old_dir))
  vim.fn.delete(outside, "rf")

  assert(message == "Not in a git repository.", "the picker should explain why it cannot open")
  assert(not selected, "the picker should not open outside a git repository")
  return true
end

-- An empty repository is valid, but there is nothing for the picker to display.
function M.test_picker_warns_for_empty_history()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  local orig_echo = vim.api.nvim_echo
  local orig_select = vim.ui.select
  local message
  local selected = false
  vim.api.nvim_echo = function(chunks)
    message = chunks[1][1]
  end
  vim.ui.select = function()
    selected = true
  end

  require("unified.commit_picker").pick()
  local warned = wait_until(function()
    return message ~= nil
  end)

  vim.api.nvim_echo = orig_echo
  vim.ui.select = orig_select
  utils.cleanup_git_repo(repo)

  assert(warned, "the picker should report an empty history")
  assert(message == "No commits to pick from.", "the picker should explain that the history is empty")
  assert(not selected, "the picker should not open when no commits are available")
  return true
end

-- Bare `:Unified` opens the picker; choosing a commit diffs the current buffer.
function M.test_no_args_opens_picker_and_diffs_choice()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Keep the test self-contained: no tree window to manage.
  require("unified.config").setup({ file_tree = { enabled = false } })

  local path = utils.create_and_commit_file(repo, "test.txt", { "line 1", "line 2" }, "Initial commit")
  vim.cmd("edit " .. path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" })
  local buffer = vim.api.nvim_get_current_buf()

  -- Stub vim.ui.select so the picker resolves to the newest commit instead of
  -- blocking on input in headless mode.
  local orig_select = vim.ui.select
  local offered
  vim.ui.select = function(items, _, on_choice)
    offered = items
    on_choice(items[1])
  end

  require("unified.command").run("")

  local offered_ok = wait_until(function()
    return offered ~= nil
  end)
  local diff_ok = offered_ok and wait_until(function()
    return buffer_has_diff(buffer)
  end)

  -- Restore before asserting so a failure can never leak the stub.
  vim.ui.select = orig_select

  assert(offered_ok, "the picker should be offered a list of commits")
  assert(#offered >= 1, "the picker should list at least one commit")
  assert(diff_ok, "choosing a commit should diff the current buffer against it")

  utils.cleanup_git_repo(repo)
  return true
end

-- When the picker is dismissed (no choice), no diff is shown.
function M.test_picker_cancel_shows_no_diff()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({ file_tree = { enabled = false } })

  local path = utils.create_and_commit_file(repo, "test.txt", { "line 1", "line 2" }, "Initial commit")
  vim.cmd("edit " .. path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" })
  local buffer = vim.api.nvim_get_current_buf()

  local orig_select = vim.ui.select
  local offered
  vim.ui.select = function(items, _, on_choice)
    offered = items
    on_choice(nil) -- user pressed <Esc>
  end

  require("unified.command").run("")

  local offered_ok = wait_until(function()
    return offered ~= nil
  end)
  -- Give any (erroneous) diff a chance to appear before asserting it did not.
  vim.wait(100, function() end, 1, false)
  local has_diff = buffer_has_diff(buffer)

  vim.ui.select = orig_select

  assert(offered_ok, "the picker should still be offered a list of commits")
  assert(not has_diff, "cancelling the picker should not show a diff")

  utils.cleanup_git_repo(repo)
  return true
end

-- Regression: the picker must diff the buffer that was focused when it was opened,
-- not whatever happens to be current when the async list_commits/selection chain
-- resolves a tick later. Switching buffers while the picker is pending used to bind
-- the diff to the wrong buffer.
function M.test_picker_diffs_origin_buffer_not_current_at_callback()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified.config").setup({ file_tree = { enabled = false } })

  local path_a = utils.create_and_commit_file(repo, "a.txt", { "a1", "a2" }, "commit a")
  local path_b = utils.create_and_commit_file(repo, "b.txt", { "b1", "b2" }, "commit b")

  -- Two modified buffers. A is the one focused when the picker is invoked.
  vim.cmd("edit " .. path_b)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified b1" })
  local buf_b = vim.api.nvim_get_current_buf()

  vim.cmd("edit " .. path_a)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified a1" })
  local buf_a = vim.api.nvim_get_current_buf()

  local orig_select = vim.ui.select
  vim.ui.select = function(items, _, on_choice)
    on_choice(items[1])
  end

  require("unified.command").run("") -- opens picker; list_commits resolves on a later tick

  -- Before that async callback fires, the current buffer changes to B. The picker
  -- must still diff A (its origin), not B.
  vim.api.nvim_set_current_buf(buf_b)

  local a_diffed = wait_until(function()
    return buffer_has_diff(buf_a)
  end)

  vim.ui.select = orig_select

  assert(a_diffed, "picker must diff the buffer it was opened from (A)")
  assert(not buffer_has_diff(buf_b), "picker must not diff the buffer that became current later (B)")

  utils.cleanup_git_repo(repo)
  return true
end

return M
