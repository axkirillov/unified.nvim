-- Test for file tree handling commit references
local vim = vim
local assert = assert

-- Import modules
local file_tree = require("unified.file_tree")
local git = require("unified.git")
local state = require("unified.state")

-- Test function
local function test_commit_file_tree()
  -- Setup: Create test environment and state
  local cwd = vim.fn.getcwd()

  -- Make sure we're in a git repo
  if not git.is_git_repo(cwd) then
    print("Test requires git repository.")
    return false
  end

  -- Test case 1: Show file tree with HEAD
  state.commit_base = "HEAD"
  local success = file_tree.show_file_tree("HEAD", false)
  assert(success, "Failed to show file tree with HEAD")

  -- Verify tree window exists
  assert(
    state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win),
    "File tree window not created for HEAD"
  )

  -- Verify buffer exists and is valid
  assert(state.file_tree_buf and vim.api.nvim_buf_is_valid(state.file_tree_buf), "File tree buffer not valid for HEAD")

  -- Test case 2: Show file tree with HEAD~1
  state.commit_base = "HEAD~1"
  success = file_tree.show_file_tree("HEAD~1", false)
  assert(success, "Failed to show file tree with HEAD~1")

  -- Verify tree window still exists and is valid
  assert(
    state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win),
    "File tree window not valid for HEAD~1"
  )

  -- Verify buffer still exists and is valid
  assert(
    state.file_tree_buf and vim.api.nvim_buf_is_valid(state.file_tree_buf),
    "File tree buffer not valid for HEAD~1"
  )

  -- Clean up: Close tree window
  if state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win) then
    vim.api.nvim_win_close(state.file_tree_win, true)
  end

  -- Reset state
  state.file_tree_win = nil
  state.file_tree_buf = nil
  state.commit_base = nil

  print("All file tree commit tests passed!")
  return true
end

-- Run the test
return {
  test_commit_file_tree = test_commit_file_tree,
}
