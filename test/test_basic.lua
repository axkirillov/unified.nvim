-- Test file for basic functionality of unified.nvim
local M = {}

-- Import test utilities
local utils = require("test.test_utils")

-- Test showing diff directly through API
function M.test_show_diff_api()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end
  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  -- Open the file and make changes
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" }) -- Change line 1
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {}) -- Delete line 3
  vim.api.nvim_buf_set_lines(0, 3, 3, false, { "new line" }) -- Add new line

  -- Call the plugin function to show diff
  local result = require("unified").show_git_diff()

  -- Get buffer to check if extmarks exist
  local buffer = vim.api.nvim_get_current_buf()
  local has_extmarks = utils.check_extmarks_exist(buffer)
  local has_signs = utils.check_signs_exist(buffer)

  -- Check that extmarks were created
  assert(result, "show_git_diff() should return true")
  assert(has_extmarks, "No diff extmarks were created")
  assert(has_signs, "No diff signs were placed")

  -- Clear diff
  utils.clear_diff_marks(buffer)

  -- Close the buffer
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test using the user command
function M.test_diff_command()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  -- Open the file and make changes
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" }) -- Change line 1
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {}) -- Delete line 3
  vim.api.nvim_buf_set_lines(0, 3, 3, false, { "new line" }) -- Add new line

  -- Log git status for debugging
  print("Git status: " .. vim.fn.system("git status"))

  -- Use user command to show diff
  vim.cmd("Unified")

  -- Get namespace to check if extmarks exist
  local buffer = vim.api.nvim_get_current_buf()
  local has_extmarks, marks = utils.check_extmarks_exist(buffer)

  -- Check that extmarks were created
  assert(has_extmarks, "No diff extmarks were created after running Unified command")

  -- Check for signs
  local has_signs = utils.check_signs_exist(buffer)
  assert(has_signs, "No diff signs were placed after running Unified command")

  -- Validate that we have some changes
  assert(#marks > 0, "No extmarks found for changes")

  -- Use command to toggle diff off
  vim.cmd("Unified toggle")
  has_extmarks, marks = utils.check_extmarks_exist(buffer)
  assert(not has_extmarks, "Extmarks were not cleared after toggle command")

  -- Close the buffer
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Debug function to test diff parsing
function M.test_diff_parsing()
  -- Create two files with known differences
  local file1 = vim.fn.tempname()
  local file2 = vim.fn.tempname()

  vim.fn.writefile({ "line 1", "line 2", "line 3", "line 4", "line 5" }, file1)
  vim.fn.writefile({ "modified line 1", "line 2", "line 4", "new line", "line 5" }, file2)

  -- Generate diff
  local diff_cmd = string.format("diff -u %s %s", file1, file2)
  local diff_output = vim.fn.system(diff_cmd)

  -- Parse the diff
  local hunks = require("unified").parse_diff(diff_output)

  -- Verify hunks were correctly parsed
  assert(#hunks > 0, "No hunks were parsed from diff output")

  -- Print diff info for debugging
  for i, hunk in ipairs(hunks) do
    print(
      string.format(
        "Hunk %d: old_start=%d, old_count=%d, new_start=%d, new_count=%d",
        i,
        hunk.old_start,
        hunk.old_count,
        hunk.new_start,
        hunk.new_count
      )
    )
    for j, line in ipairs(hunk.lines) do
      print(string.format("  Line %d: %s", j, line))
    end
  end

  -- Clean up
  vim.fn.delete(file1)
  vim.fn.delete(file2)

  return true
end

-- Test Git diff functionality
function M.test_git_diff()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  -- Open the file and make changes
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" }) -- Change line 1
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {}) -- Delete line 3
  vim.api.nvim_buf_set_lines(0, 3, 3, false, { "new line" }) -- Add new line

  -- Call the plugin function to show git diff
  local result = require("unified").show_git_diff()

  -- Get buffer to check if extmarks exist
  local buffer = vim.api.nvim_get_current_buf()
  local has_extmarks = utils.check_extmarks_exist(buffer)
  local has_signs = utils.check_signs_exist(buffer)

  -- Check that extmarks were created
  assert(result, "show_git_diff() should return true")
  assert(has_extmarks, "No diff extmarks were created")
  assert(has_signs, "No diff signs were placed")

  -- Clear diff
  utils.clear_diff_marks(buffer)

  -- Close the buffer
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

return M
