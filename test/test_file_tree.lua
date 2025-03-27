local utils = require("test.test_utils")
local M = {}

-- Test file tree creation showing only files in diff
function M.test_file_tree_diff_only_mode()
  -- Set up test environment
  local repo = utils.create_git_repo()
  if not repo then
    print("Failed to create git repository, skipping test")
    return true
  end
  
  -- Create multiple test files and commit them
  local file1_path = utils.create_and_commit_file(repo, "test1.txt", {"line 1", "line 2", "line 3"}, "Initial commit - file 1")
  local file2_path = utils.create_and_commit_file(repo, "test2.txt", {"line A", "line B", "line C"}, "Add file 2")
  local file3_path = utils.create_and_commit_file(repo, "test3.txt", {"test file 3"}, "Add file 3")
  
  -- Create a subdirectory with a file
  local subdir_path = repo.repo_dir .. "/subdir"
  vim.fn.mkdir(subdir_path, "p")
  local file4_path = utils.create_and_commit_file(repo, "subdir/test4.txt", {"subdir file"}, "Add subdir file")
  
  -- Modify only one file
  vim.cmd("edit " .. file1_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, {"modified line 1"})
  
  -- Store current window for later
  local main_win = vim.api.nvim_get_current_win()
  
  -- Show diff with file tree in diff-only mode
  require("unified").show_diff()
  
  -- Check if file tree window exists
  local file_tree_win = require("unified").file_tree_win
  assert(file_tree_win and vim.api.nvim_win_is_valid(file_tree_win), "File tree window should exist")
  
  -- Check if file tree buffer exists
  local file_tree_buf = require("unified").file_tree_buf
  assert(file_tree_buf and vim.api.nvim_buf_is_valid(file_tree_buf), "File tree buffer should exist")
  
  -- Check file tree buffer contents
  local tree_lines = vim.api.nvim_buf_get_lines(file_tree_buf, 0, -1, false)
  
  -- Verify the tree only shows the modified file
  local found_modified_file = false
  local found_unmodified_file = false
  
  for _, line in ipairs(tree_lines) do
    if line:match("test1%.txt") then
      found_modified_file = true
    elseif line:match("test2%.txt") or line:match("test3%.txt") or line:match("test4%.txt") then
      found_unmodified_file = true
    end
  end
  
  assert(found_modified_file, "Modified file should be shown in the tree")
  assert(not found_unmodified_file, "Unmodified files should not be shown in diff-only mode")
  
  -- Test with no changes
  -- Create a new file with no changes
  vim.cmd("edit " .. file2_path)
  
  -- Show diff with file tree (should show an empty tree)
  require("unified").show_diff()
  
  -- Check file tree buffer contents again
  tree_lines = vim.api.nvim_buf_get_lines(file_tree_buf, 0, -1, false)
  
  -- Verify the tree shows a "no changes" message
  local found_no_changes_message = false
  for _, line in ipairs(tree_lines) do
    if line:match("No modified files") then
      found_no_changes_message = true
      break
    end
  end
  
  assert(found_no_changes_message, "Tree should display 'No modified files' message when no changes exist")
  
  -- Now test tree-all mode showing all files
  vim.api.nvim_set_current_win(main_win)
  
  -- Show file tree in full mode
  require("unified").show_file_tree(nil, true)
  
  -- Check file tree buffer contents
  tree_lines = vim.api.nvim_buf_get_lines(file_tree_buf, 0, -1, false)
  
  -- Verify the tree shows all files
  local all_files_found = 0
  for _, line in ipairs(tree_lines) do
    if line:match("test1%.txt") then
      all_files_found = all_files_found + 1
    elseif line:match("test2%.txt") then
      all_files_found = all_files_found + 1
    elseif line:match("test3%.txt") then
      all_files_found = all_files_found + 1
    elseif line:match("test4%.txt") then
      all_files_found = all_files_found + 1
    end
  end
  
  assert(all_files_found >= 4, "All 4 files should be shown in tree-all mode")
  
  -- Clean up
  vim.cmd("bdelete!")
  require("unified").toggle_diff() -- Close the file tree
  utils.cleanup_git_repo(repo)
  
  return true
end

-- Add test to runner
return M