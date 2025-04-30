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

  local success = file_tree.show("HEAD")
  assert(success, "Failed to show file tree with HEAD")

  -- Verify tree window exists
  assert(
    state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win),
    "File tree window not created for HEAD"
  )

  -- Verify buffer exists and is valid
  assert(state.file_tree_buf and vim.api.nvim_buf_is_valid(state.file_tree_buf), "File tree buffer not valid for HEAD")

  success = file_tree.show("HEAD~1")
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

  state.reset_file_tree_state()

  print("All file tree commit tests passed!")
  return true
end

-- Run the test
return {
  test_commit_file_tree = test_commit_file_tree,
}
