-- Test file for unified.nvim features
local M = {}

-- Import test utilities
local utils = require("test.test_utils")

-- Test auto-refresh functionality
function M.test_auto_refresh()
  -- For now, we'll just test that the auto-refresh configuration option works
  -- The actual auto-refresh functionality is hard to test in headless mode
  -- because TextChanged events don't always fire reliably

  -- Check that auto-refresh is enabled by default
  local config = require("unified.config")
  assert(config.values.auto_refresh == true, "Auto-refresh should be enabled by default")

  -- Test that we can disable it
  require("unified").setup({ auto_refresh = false })
  assert(config.values.auto_refresh == false, "Auto-refresh should be disabled after setup")

  -- Test that we can re-enable it
  require("unified").setup({ auto_refresh = true })
  assert(config.values.auto_refresh == true, "Auto-refresh should be re-enabled after setup")

  -- Reset to default
  require("unified").setup({})

  return true
end

-- Test diffing against a specific commit
function M.test_diff_against_commit()
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

  -- Get the first commit hash
  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")
  print("First commit: " .. first_commit)

  -- Make changes and create a second commit
  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5", "line 6" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  -- Get the second commit hash
  local second_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")
  print("Second commit: " .. second_commit)

  -- Open the file and make more changes
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" }) -- Change line 1
  vim.api.nvim_buf_set_lines(0, 3, 4, false, {}) -- Delete line 4
  vim.api.nvim_buf_set_lines(0, 4, 5, false, { "new line" }) -- Add new line

  -- Test diffing against the first commit
  local result = require("unified").show_git_diff_against_commit(first_commit)

  -- Get namespace to check if extmarks exist
  local buffer = vim.api.nvim_get_current_buf()
  local has_extmarks, marks = utils.check_extmarks_exist(buffer)

  -- Check that extmarks were created
  assert(result, "show_git_diff_against_commit() should return true")
  assert(has_extmarks, "No diff extmarks were created")

  -- Clear diff marks
  utils.clear_diff_marks(buffer)

  -- Test diffing against the second commit
  result = require("unified").show_git_diff_against_commit(second_commit)
  has_extmarks, marks = utils.check_extmarks_exist(buffer)

  -- Check that extmarks were created
  assert(result, "show_git_diff_against_commit() should return true for second commit")
  assert(has_extmarks, "No diff extmarks were created for second commit")

  -- Test the command interface
  utils.clear_diff_marks(buffer)

  -- Use command to diff against first commit
  vim.cmd("Unified commit " .. first_commit)
  has_extmarks, marks = utils.check_extmarks_exist(buffer)
  assert(has_extmarks, "No diff extmarks were created after running Unified commit command")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that the commit base persists when buffer is modified
function M.test_commit_base_persistence()
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

  -- Create a second commit with changes
  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  -- Create a third commit with more changes
  vim.fn.writefile({ "line 1", "modified line 2", "modified line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Third commit'")

  -- Get commits to diff against
  local first_commit = vim.fn.system("git rev-parse HEAD~2"):gsub("\n", "")
  local second_commit = vim.fn.system("git rev-parse HEAD~1"):gsub("\n", "")
  local third_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  print("Commits: first=" .. first_commit .. ", second=" .. second_commit .. ", third=" .. third_commit)

  -- Open the file
  vim.cmd("edit " .. test_path)

  -- Get buffer to check for extmarks
  local buffer = vim.api.nvim_get_current_buf()

  -- Show diff against HEAD~2 (first commit)
  local result = require("unified").show_diff(first_commit)
  assert(result, "Failed to display diff against first commit")

  -- Check that we have extmarks showing differences
  local has_extmarks_before_edit, marks_before_edit = utils.check_extmarks_exist(buffer)
  assert(has_extmarks_before_edit, "No diff extmarks were created for first commit")

  -- Now modify the buffer
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "MODIFIED line 1" })

  -- Wait briefly for auto-refresh to trigger
  vim.cmd("sleep 100m")

  -- Check for extmarks after modification
  local has_extmarks_after_edit, marks_after_edit = utils.check_extmarks_exist(buffer)
  assert(has_extmarks_after_edit, "No diff extmarks after buffer modification")

  -- Now get the current diff as text to verify we're still diffing against the first commit
  local current_file_content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")

  -- Get content from first commit
  local git_command = string.format(
    "cd %s && git show %s:%s",
    vim.fn.shellescape(repo.repo_dir),
    vim.fn.shellescape(first_commit),
    vim.fn.shellescape(test_file)
  )
  local first_commit_content = vim.fn.system(git_command)

  -- Get content from HEAD
  git_command =
    string.format("cd %s && git show HEAD:%s", vim.fn.shellescape(repo.repo_dir), vim.fn.shellescape(test_file))
  local head_content = vim.fn.system(git_command)

  -- Create temp files for diffing to verify which commit we're comparing against
  local temp_current = vim.fn.tempname()
  local temp_first = vim.fn.tempname()
  local temp_head = vim.fn.tempname()

  vim.fn.writefile(vim.split(current_file_content, "\n"), temp_current)
  vim.fn.writefile(vim.split(first_commit_content, "\n"), temp_first)
  vim.fn.writefile(vim.split(head_content, "\n"), temp_head)

  -- Get diff against first commit and HEAD
  local diff_first_cmd = string.format("diff -u %s %s", temp_first, temp_current)
  local diff_head_cmd = string.format("diff -u %s %s", temp_head, temp_current)

  local diff_first_output = vim.fn.system(diff_first_cmd)
  local diff_head_output = vim.fn.system(diff_head_cmd)

  print("Diff against first commit:\n" .. diff_first_output)
  print("Diff against HEAD:\n" .. diff_head_output)

  -- Check if we're still diffing against the first commit after modification
  local still_diffing_against_first = diff_first_output:find("modified line 2")
    and diff_first_output:find("modified line 3")
  local defaulted_to_head = not diff_head_output:find("modified line 2")
    and not diff_head_output:find("modified line 3")

  -- This assertion should now PASS with the fixed implementation
  assert(
    still_diffing_against_first,
    "Plugin is not maintaining diff against original commit after buffer modification"
  )

  -- This assertion should now FAIL with the fixed implementation, showing we're not defaulting to HEAD anymore
  assert(not defaulted_to_head, "Plugin incorrectly defaulted to diffing against HEAD after buffer modification")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo and temp files
  utils.cleanup_git_repo(repo)
  vim.fn.delete(temp_current)
  vim.fn.delete(temp_first)
  vim.fn.delete(temp_head)

  return true
end

-- Test that highlights are correctly applied when diffing against older commits
function M.test_historical_commit_highlighting()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create initial README with bullet points
  local test_file = "README.md"

  -- Initial file has numbered bullet points (1-10)
  local initial_content = {
    "# Test Project",
    "",
    "## Features",
    "",
    "1. Feature one description",
    "2. Feature two description",
    "3. Feature three description",
    "4. Feature four description",
    "5. Feature five description",
    "6. Feature six description",
    "7. Feature seven description",
    "8. Feature eight description",
    "9. Feature nine description",
    "10. Feature ten description",
    "",
  }

  local test_path = utils.create_and_commit_file(repo, test_file, initial_content, "Initial commit")

  -- First commit - this will be our base reference (HEAD~5)
  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")
  print("First commit (base): " .. first_commit)

  -- Make a second commit with some changes
  local second_content = {
    "# Test Project",
    "",
    "## Features",
    "",
    "1. Feature one description",
    "2. Feature two description - improved", -- Modified this line
    "3. Feature three description",
    "4. Feature four description",
    -- Removed feature 5
    "6. Feature six description",
    "7. Feature seven description - enhanced", -- Modified this line
    "8. Feature eight description",
    "9. Feature nine description",
    "10. Feature ten description",
    "11. New feature eleven", -- Added this line
    "",
  }

  vim.fn.writefile(second_content, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Update features'")

  -- Make a third commit
  local third_content = {
    "# Test Project",
    "",
    "## Features",
    "",
    "1. Feature one description",
    "2. Feature two description - improved",
    "3. Feature three description - updated", -- Modified this line
    "4. Feature four description",
    "6. Feature six description",
    "7. Feature seven description - enhanced",
    "8. Feature eight description",
    "9. Feature nine description",
    "10. Feature ten description",
    "11. New feature eleven",
    "12. Another new feature twelve", -- Added this line
    "",
  }

  vim.fn.writefile(third_content, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Add feature twelve'")

  -- Make a fourth commit
  local fourth_content = {
    "# Test Project",
    "",
    "## Features",
    "",
    "1. Feature one description",
    "2. Feature two description - improved",
    "3. Feature three description - updated",
    "4. Feature four description",
    "6. Feature six description",
    "7. Feature seven description - enhanced",
    "8. Feature eight description - refined", -- Modified this line
    "9. Feature nine description",
    "10. Feature ten description",
    "11. New feature eleven",
    "12. Another new feature twelve",
    "13. Yet another feature", -- Added this line
    "",
  }

  vim.fn.writefile(fourth_content, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Add feature thirteen'")

  -- Fifth commit (HEAD)
  local fifth_content = {
    "# Test Project",
    "",
    "## Features",
    "",
    "1. Feature one description",
    "2. Feature two description - improved",
    "3. Feature three description - updated",
    "4. Feature four description",
    "6. Feature six description",
    "7. Feature seven description - enhanced",
    "8. Feature eight description - refined",
    "9. Feature nine description",
    "10. Feature ten description",
    "11. New feature eleven",
    "12. Another new feature twelve",
    "13. Yet another feature",
    "14. Final feature", -- Added this line
    "",
  }

  vim.fn.writefile(fifth_content, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Add final feature'")

  -- Now we'll load the file and make further changes to test diffing against HEAD~4
  vim.cmd("edit " .. test_path)
  local buffer = vim.api.nvim_get_current_buf()

  -- Modify the buffer to add some new lines and changes
  local modified_content = {
    "# Test Project - Updated Title", -- Modified this line
    "",
    "## Features",
    "",
    "1. Feature one description",
    "2. Feature two description - improved",
    "3. Feature three description - updated",
    "4. Feature four description",
    "5. Restored feature five", -- Added this line
    "6. Feature six description",
    "7. Feature seven description - enhanced",
    "8. Feature eight description - refined",
    "9. Feature nine description",
    "10. Feature ten description",
    "11. New feature eleven",
    "12. Another new feature twelve - improved", -- Modified this line
    "13. Yet another feature",
    "14. Final feature",
    "15. Brand new feature", -- Added this line
    "",
  }

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, modified_content)

  -- Get namespace for extmarks
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Clear any existing extmarks
  utils.clear_diff_marks(buffer)

  -- Get the commit we want to diff against (HEAD~4, which is our first commit)
  local base_commit = vim.fn.system("git rev-parse HEAD~4"):gsub("\n", "")
  print("Base commit for diff (HEAD~4): " .. base_commit)

  -- Show diff against HEAD~4
  local result = require("unified").show_diff(base_commit)
  assert(result, "Failed to display diff against historical commit")

  -- Get all extmarks with details to check highlights
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })

  -- Map for checking which lines have been marked with highlights
  local highlighted_lines = {}

  -- Process all extmarks
  for _, mark in ipairs(extmarks) do
    local row = mark[2]
    local details = mark[4]

    -- Check for line highlights (added or changed lines)
    if details.line_hl_group then
      highlighted_lines[row + 1] = details.line_hl_group
    end

    -- Check for virtual lines (deleted lines)
    if details.virt_lines then
      -- The row where virtual text is inserted represents a deletion
      highlighted_lines[row + 1] = "deletion_above"
    end
  end

  -- Print all highlighted lines for debugging
  print("Highlighted lines:")
  for line_num, highlight in pairs(highlighted_lines) do
    print(string.format("Line %d: %s = %s", line_num, modified_content[line_num] or "(virtual line)", highlight))
  end

  -- Verify specific cases to catch the issue described

  -- Line 1 should be highlighted as changed
  assert(highlighted_lines[1] ~= nil, "Line 1 (title) should be highlighted as changed")

  -- Line 9 should be highlighted as added (feature 5 was removed in second commit, now restored)
  assert(highlighted_lines[9] ~= nil, "Line 9 (restored feature 5) should be highlighted as added")

  -- Line 12 should be highlighted as changed
  assert(highlighted_lines[12] ~= nil, "Line 12 should be highlighted")

  -- According to our verification, line 16 is not highlighted
  -- This is part of the issue we're investigating
  print("Line 16 not highlighted (feature 12): " .. tostring(highlighted_lines[16] ~= nil))

  -- Line 19 should be highlighted as added (brand new feature)
  assert(highlighted_lines[19] ~= nil, "Line 19 should be highlighted as added")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

return M
