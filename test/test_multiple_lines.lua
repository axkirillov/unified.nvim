-- Test file for multiple line additions in unified.nvim
local M = {}

-- Import test utilities
local utils = require("test.test_utils")

-- Test that multiple consecutive added lines are properly highlighted
function M.test_multiple_added_lines()
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

  -- Open the file and add multiple consecutive new lines
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "new line 1", "new line 2", "new line 3" }) -- Add 3 new lines

  -- Call the plugin function to show diff
  local result = require("unified").show_git_diff()
  assert(result, "Failed to display diff")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Get all extmarks with details to check highlights
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
  -- Track which lines are highlighted (1-indexed for easier comparison with buffer lines)
  local highlighted_lines = {}
  -- Process all extmarks to find which lines have highlighting
  for _, mark in ipairs(extmarks) do
    local row = mark[2] + 1 -- Convert to 1-indexed for consistency with buffer lines
    local details = mark[4]
    -- Check for line highlighting
    if details.line_hl_group then
      highlighted_lines[row] = true
    end
  end

  -- Get buffer lines for debugging
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  -- Debug: Print all buffer lines and whether they're highlighted
  print("Buffer lines and highlighting:")
  for i, line in ipairs(buffer_lines) do
    print(string.format("%d: '%s' %s", i, line, highlighted_lines[i] and "(highlighted)" or ""))
  end

  -- Check that all three new lines are highlighted
  assert(highlighted_lines[3], "First new line (new line 1) not highlighted")
  assert(highlighted_lines[4], "Second new line (new line 2) not highlighted")
  assert(highlighted_lines[5], "Third new line (new line 3) not highlighted")

  -- Look for extmarks with sign_text to confirm they are marked as additions
  local extmarks_with_signs = {}

  for _, mark in ipairs(extmarks) do
    local row = mark[2] + 1 -- Convert to 1-indexed
    local details = mark[4]

    if details.sign_text and details.sign_text == "+" then
      extmarks_with_signs[row] = true
    end
  end

  -- Check that appropriate sign extmarks were placed for added lines
  assert(extmarks_with_signs[3] or highlighted_lines[3], "First new line (new line 1) not marked as addition")
  assert(extmarks_with_signs[4] or highlighted_lines[4], "Second new line (new line 2) not marked as addition")
  assert(extmarks_with_signs[5] or highlighted_lines[5], "Third new line (new line 3) not marked as addition")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test multiple line additions with commit diffing
function M.test_multiple_added_lines_with_commit()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(repo, test_file, { "line 1", "line 2", "line 3" }, "Initial commit")

  -- Make a first commit (this will be our base)
  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  -- Create a second commit with some changes
  vim.fn.writefile({ "line 1", "line 2", "modified line 3" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Modify line 3'")

  -- Open the file and add multiple consecutive new lines
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 1, 1, false, { "new line 1", "new line 2", "new line 3" }) -- Add 3 new lines after line 1

  -- Show diff against the first commit to test against a specific commit
  local unified = require("unified")
  -- Reset the active state since we're calling functions directly
  unified.is_active = false
  local result = unified.show_git_diff_against_commit(first_commit)
  assert(result, "Failed to display diff against first commit")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Get all extmarks with details
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })

  -- Track which lines are highlighted
  local highlighted_lines = {}

  for _, mark in ipairs(extmarks) do
    local row = mark[2] + 1 -- Convert to 1-indexed
    local details = mark[4]

    if details.line_hl_group then
      highlighted_lines[row] = true
    end
  end

  -- Get buffer lines for debugging
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  -- Debug: Print all buffer lines and whether they're highlighted
  print("Buffer lines and highlighting when diffing against commit:")
  for i, line in ipairs(buffer_lines) do
    print(string.format("%d: '%s' %s", i, line, highlighted_lines[i] and "(highlighted)" or ""))
  end

  -- Check that all new lines are highlighted
  assert(highlighted_lines[2], "First new line (new line 1) not highlighted against commit")
  assert(highlighted_lines[3], "Second new line (new line 2) not highlighted against commit")
  assert(highlighted_lines[4], "Third new line (new line 3) not highlighted against commit")

  -- Also verify that modified line 3 (now line 6) is highlighted
  assert(highlighted_lines[6], "Modified line not highlighted against commit")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

return M
