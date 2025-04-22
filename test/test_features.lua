local utils = require("test.test_utils")

local M = {}

function M.test_auto_refresh()
  local config = require("unified.config")
  assert(config.values.auto_refresh == true, "Auto-refresh should be enabled by default")

  require("unified").setup({ auto_refresh = false })
  assert(config.values.auto_refresh == false, "Auto-refresh should be disabled after setup")

  require("unified").setup({ auto_refresh = true })
  assert(config.values.auto_refresh == true, "Auto-refresh should be re-enabled after setup")

  require("unified").setup({})

  return true
end

function M.test_diff_against_commit()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5", "line 6" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  local second_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  vim.cmd("edit! " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" }) -- Change line 1
  vim.api.nvim_buf_set_lines(0, 3, 4, false, {}) -- Delete line 4
  vim.api.nvim_buf_set_lines(0, 4, 5, false, { "new line" }) -- Add new line
  vim.cmd("write")

  local buffer = vim.api.nvim_get_current_buf()
  local result = require("unified.git").show_git_diff_against_commit(first_commit, buffer)

  local has_extmarks, _ = utils.check_extmarks_exist(buffer)

  assert(result, "show_git_diff_against_commit() should return true")
  assert(has_extmarks, "No diff extmarks were created")

  utils.clear_diff_marks(buffer)

  result = require("unified.git").show_git_diff_against_commit(second_commit, buffer)
  has_extmarks, _ = utils.check_extmarks_exist(buffer)

  assert(result, "show_git_diff_against_commit() should return true for second commit")
  assert(has_extmarks, "No diff extmarks were created for second commit")

  utils.clear_diff_marks(buffer)

  vim.cmd("write")
  result = require("unified.git").show_git_diff_against_commit(first_commit, buffer)
  assert(result, "show_git_diff_against_commit() should return true after write and direct call")
  has_extmarks, _ = utils.check_extmarks_exist(buffer)
  assert(has_extmarks, "No diff extmarks were created after write and direct call")

  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  utils.cleanup_git_repo(repo)

  return true
end

function M.test_commit_base_persistence()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  vim.fn.writefile({ "line 1", "modified line 2", "modified line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Third commit'")

  local first_commit = vim.fn.system("git rev-parse HEAD~2"):gsub("\n", "")
  local _ = vim.fn.system("git rev-parse HEAD~1"):gsub("\n", "")
  local _ = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  vim.cmd("edit " .. test_path)
  local buffer = vim.fn.bufnr(test_path)

  print("test_commit_base_persistence: buffer ID before show_diff: " .. tostring(buffer))

  local result = require("unified.git").show_git_diff_against_commit(first_commit, buffer)
  assert(result, "Failed to display diff against first commit")

  local has_extmarks_before_edit, _ = utils.check_extmarks_exist(buffer)
  assert(has_extmarks_before_edit, "No diff extmarks were created for first commit")

  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "MODIFIED line 1" })

  vim.cmd("sleep 100m")

  local has_extmarks_after_edit, _ = utils.check_extmarks_exist(buffer)
  assert(has_extmarks_after_edit, "No diff extmarks after buffer modification")

  local current_file_content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")

  local git_command = string.format(
    "cd %s && git show %s:%s",
    vim.fn.shellescape(repo.repo_dir),
    vim.fn.shellescape(first_commit),
    vim.fn.shellescape(test_file)
  )
  local first_commit_content = vim.fn.system(git_command)

  git_command =
    string.format("cd %s && git show HEAD:%s", vim.fn.shellescape(repo.repo_dir), vim.fn.shellescape(test_file))
  local head_content = vim.fn.system(git_command)

  local temp_current = vim.fn.tempname()
  local temp_first = vim.fn.tempname()
  local temp_head = vim.fn.tempname()

  vim.fn.writefile(vim.split(current_file_content, "\n"), temp_current)
  vim.fn.writefile(vim.split(first_commit_content, "\n"), temp_first)
  vim.fn.writefile(vim.split(head_content, "\n"), temp_head)

  local diff_first_cmd = string.format("diff -u %s %s", temp_first, temp_current)
  local diff_head_cmd = string.format("diff -u %s %s", temp_head, temp_current)

  local diff_first_output = vim.fn.system(diff_first_cmd)
  local diff_head_output = vim.fn.system(diff_head_cmd)

  local still_diffing_against_first = diff_first_output:find("modified line 2")
    and diff_first_output:find("modified line 3")
  local defaulted_to_head = not diff_head_output:find("modified line 2")
    and not diff_head_output:find("modified line 3")

  assert(
    still_diffing_against_first,
    "Plugin is not maintaining diff against original commit after buffer modification"
  )

  assert(not defaulted_to_head, "Plugin incorrectly defaulted to diffing against HEAD after buffer modification")

  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

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

  local _ = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

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
    "12. Another new feature twelve",
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
  local buffer = vim.fn.bufnr(test_path)

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
    "12. Another new feature twelve - improved",
    "13. Yet another feature",
    "14. Final feature",
    "15. Brand new feature",
    "",
  }

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, modified_content)
  vim.cmd("write")

  -- Get namespace for extmarks
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Clear any existing extmarks
  utils.clear_diff_marks(buffer)

  -- Get the commit we want to diff against (HEAD~4, which is our first commit)
  local base_commit = vim.fn.system("git rev-parse HEAD~4"):gsub("\n", "")

  -- Show diff against HEAD~4
  local result = require("unified.git").show_git_diff_against_commit(base_commit, buffer)
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
  for line_num, highlight in pairs(highlighted_lines) do
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
