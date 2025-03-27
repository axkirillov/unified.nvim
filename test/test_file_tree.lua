local utils = require("test.test_utils")
local M = {}

-- Test file tree creation
function M.test_file_tree_creation()
  -- Set up test environment
  local repo = utils.create_git_repo()
  if not repo then
    print("Failed to create git repository, skipping test")
    return true
  end
  
  -- Create test file and commit it
  local file_path = utils.create_and_commit_file(repo, "test.txt", {"line 1", "line 2", "line 3"}, "Initial commit")
  
  -- Open the file
  vim.cmd("edit " .. file_path)
  
  -- Make a change to the buffer
  vim.api.nvim_buf_set_lines(0, 0, 1, false, {"modified line 1"})
  
  -- Store current window for later
  local main_win = vim.api.nvim_get_current_win()
  
  -- Show diff with file tree
  local result = require("unified").show_diff()
  assert(result, "show_diff() should return true")
  
  -- Check if file tree window exists
  local file_tree_win = require("unified").file_tree_win
  assert(file_tree_win and vim.api.nvim_win_is_valid(file_tree_win), "File tree window should exist")
  
  -- Check if file tree buffer exists and has content
  local file_tree_buf = require("unified").file_tree_buf
  assert(file_tree_buf and vim.api.nvim_buf_is_valid(file_tree_buf), "File tree buffer should exist")
  
  -- Check file tree buffer contents
  local tree_lines = vim.api.nvim_buf_get_lines(file_tree_buf, 0, -1, false)
  assert(#tree_lines > 0, "File tree buffer should have content")
  
  -- Test closing the tree with toggle
  require("unified").toggle_diff()
  
  -- Check if tree window is closed
  assert(not vim.api.nvim_win_is_valid(file_tree_win), "File tree window should be closed after toggle")
  
  -- Clean up
  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  
  return true
end

-- Add test to runner
return M