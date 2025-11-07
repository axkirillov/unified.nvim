-- Tests for hunk-level actions (stage / unstage / revert)
local M = {}

local utils = require("test.test_utils")

local function assert_true(cond, msg)
  assert(cond, msg or "assertion failed")
end

local function assert_eq(a, b, msg)
  assert(a == b, msg or string.format("Expected %s, got %s", vim.inspect(b), vim.inspect(a)))
end

-- Create a repo with a test file committed, return repo table and absolute path
local function setup_repo_with_file(initial_lines)
  local repo = utils.create_git_repo()
  if not repo then
    return nil, nil
  end
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(repo, test_file, initial_lines, "Initial commit")
  return repo, test_path
end

local function git(repo, cmd)
  return vim.fn.system("cd " .. repo.repo_dir .. " && " .. cmd), vim.v.shell_error
end

-- Stage a single added-line hunk and verify it appears in the index
function M.test_stage_hunk_added_line()
  local repo, path = setup_repo_with_file({ "line 1", "line 2", "line 3", "line 4", "line 5" })
  if not repo then
    return true
  end

  -- Open and modify first line to create a hunk
  vim.cmd("edit " .. path)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "modified line 1" })
  vim.cmd("write")

  -- Render diff against HEAD so hunks are known (not strictly required for actions)
  require("unified.git").show_git_diff_against_commit("HEAD", buf)

  -- Place cursor in the changed hunk
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Stage the current hunk
  require("unified.hunk_actions").stage_hunk()

  -- Verify the file is in the index diff
  local out = git(repo, "git diff --cached --name-only -- test.txt")
  assert_true(tostring(out):match("test.txt") ~= nil, "Expected test.txt to be staged")

  -- Cleanup
  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

-- Unstage a previously staged hunk and verify it is removed from the index
function M.test_unstage_staged_hunk()
  local repo, path = setup_repo_with_file({ "line 1", "line 2", "line 3", "line 4", "line 5" })
  if not repo then
    return true
  end

  vim.cmd("edit " .. path)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "modified line 1" })
  vim.cmd("write")
  require("unified.git").show_git_diff_against_commit("HEAD", buf)

  -- Stage first
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  require("unified.hunk_actions").stage_hunk()
  local out = git(repo, "git diff --cached --name-only -- test.txt")
  assert_true(tostring(out):match("test.txt") ~= nil, "Expected test.txt to be staged before unstage")

  -- Unstage the same hunk
  require("unified.hunk_actions").unstage_hunk()
  local out2 = git(repo, "git diff --cached --name-only -- test.txt")
  -- Should be empty (no staged changes for the file)
  assert_true(not tostring(out2):match("test.txt"), "Expected test.txt to be removed from index after unstage")

  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

-- Revert a hunk from the working tree and verify file content restored
function M.test_revert_hunk_added_line()
  local initial = { "line 1", "line 2", "line 3", "line 4", "line 5" }
  local repo, path = setup_repo_with_file(initial)
  if not repo then
    return true
  end

  vim.cmd("edit " .. path)
  local buf = vim.api.nvim_get_current_buf()
  -- Modify line 3 to create a hunk in the middle
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "modified line 3" })
  vim.cmd("write")
  require("unified.git").show_git_diff_against_commit("HEAD", buf)

  -- Cursor on line 3 hunk
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  -- Revert the hunk from working tree
  require("unified.hunk_actions").revert_hunk()

  -- Ensure buffer reflects on-disk change
  vim.cmd("checktime")

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Expect line 3 restored to original
  assert_eq(lines[3], initial[3], "Expected line 3 to be restored after revert_hunk")

  -- And file should have no diff for that hunk anymore
  local diffout = git(repo, "git diff -- test.txt")
  -- It could still have other differences, but should not contain "modified line 3"
  assert_true(not tostring(diffout):match("modified line 3"), "Unexpected leftover diff content for reverted hunk")

  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

return M
