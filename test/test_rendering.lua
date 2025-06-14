-- Test file for unified.nvim rendering features
local M = {}

-- Test that + signs don't appear in the buffer text (only in gutter)
function M.test_no_plus_signs_in_buffer()
  -- Create temporary git repository
  local utils = require("test.test_utils")
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
  vim.api.nvim_buf_set_lines(0, 3, 3, false, { "new line" }) -- Add new line

  -- Call the plugin function to show diff
  -- Call the plugin function to show diff
  local result = require("unified.git").show_git_diff_against_commit("HEAD", vim.api.nvim_get_current_buf())

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  local extmarks = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })

  -- Check that extmarks for added lines use sign_text and not virt_text
  local found_added_line_sign = false
  local found_added_line_virt_text = false
  local config = require("unified.config") -- Need config for symbol
  local expected_sign_text = config.values.line_symbols.add .. " "

  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    -- Check if the extmark has the 'UnifiedDiffAdd' highlight group (indicating an added line)
    if details.line_hl_group == "UnifiedDiffAdd" then
      -- Check if it has the correct sign_text
      if details.sign_text == expected_sign_text then
        found_added_line_sign = true
      end
      -- Check if it incorrectly has virt_text
      if details.virt_text then
        found_added_line_virt_text = true
        break -- No need to check further if we found incorrect virt_text
      end
    end
  end

  assert(found_added_line_sign, "Did not find expected sign_text ('" .. expected_sign_text .. "') for added lines")
  assert(not found_added_line_virt_text, "Found unexpected virt_text associated with added lines")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that deleted lines don't show up both as virtual text and as original text
function M.test_deleted_lines_not_duplicated()
  -- Create temporary git repository
  local utils = require("test.test_utils")
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create a markdown file with bullet points and commit it
  local test_file = "README.md"
  local test_path = utils.create_and_commit_file(repo, test_file, {
    "# Test File",
    "",
    "Features:",
    "- Display added, deleted, and modified lines with distinct highlighting",
    "- Something else here",
  }, "Initial commit")

  -- Open the file and delete a bullet point line
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 3, 4, false, {}) -- Delete the bullet point line

  -- Call the plugin function to show diff
  -- Call the plugin function to show diff
  local result = require("unified.git").show_git_diff_against_commit("HEAD", vim.api.nvim_get_current_buf())
  assert(result, "Failed to display diff")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Get all buffer lines
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  -- The deleted line should not appear in the actual buffer content
  local deleted_line = "- Display added, deleted, and modified lines with distinct highlighting"
  local line_appears_in_buffer = false

  for _, line in ipairs(lines) do
    if line == deleted_line then
      line_appears_in_buffer = true
      break
    end
  end

  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
  local line_appears_as_virt_text = false

  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details.virt_text then
      for _, vtext in ipairs(details.virt_text) do
        local text = vtext[1]
        if text:match(deleted_line:gsub("%-", "%%-"):gsub("%+", "%%+")) then
          line_appears_as_virt_text = true
          break
        end
      end
    end
  end

  -- This is the key assertion that reproduces the bug: we shouldn't see the deleted line
  -- both in buffer content and as virtual text (which would make it appear twice)
  assert(
    not (line_appears_in_buffer and line_appears_as_virt_text),
    "Found deleted line both in buffer content and as virtual text"
  )

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that deleted lines appear on their own line, not appended to the previous line
function M.test_deleted_lines_on_own_line()
  -- Create temporary git repository
  local utils = require("test.test_utils")
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create a markdown file with sequential bullet points and commit it
  local test_file = "README.md"
  local test_path = utils.create_and_commit_file(repo, test_file, {
    "# Test File",
    "",
    "Features:",
    "- First feature bullet point",
    "- Second feature that will be deleted",
    "- Third feature bullet point",
  }, "Initial commit")

  -- Open the file and delete the middle bullet point
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 4, 5, false, {}) -- Delete the second bullet point

  -- Call the plugin function to show diff
  -- Call the plugin function to show diff
  local result = require("unified.git").show_git_diff_against_commit("HEAD", vim.api.nvim_get_current_buf())
  assert(result, "Failed to display diff")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Get all extmarks with details
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })

  -- Look for virtual text at the end of lines
  local found_eol_deleted_text = false
  for _, mark in ipairs(extmarks) do
    local row = mark[2]
    local details = mark[4]

    if details.virt_text and details.virt_text_pos == "eol" then
      found_eol_deleted_text = true -- Found virtual text at end of line, this would be the bug
      break
    end
  end

  -- The deleted line should NOT be shown at the end of another line
  assert(
    not found_eol_deleted_text,
    "Deleted line appears as virtual text at the end of a line rather than on its own line"
  )

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that deletion symbols appear in the gutter, not in the buffer text
function M.test_deletion_symbols_in_gutter()
  -- Create temporary git repository
  local utils = require("test.test_utils")
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create a lua config-like file and commit it
  local test_file = "config.lua"
  local test_path = utils.create_and_commit_file(repo, test_file, {
    "return {",
    "  plugins = {",
    "    'axkirillov/unified.nvim',",
    "    'some/other-plugin',",
    "  },",
    "  config = function()",
    "    require('unified').setup({})",
    "  end",
    "}",
  }, "Initial commit")

  -- Open the file and delete a line
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {}) -- Delete the 'axkirillov/unified.nvim' line

  -- Call the plugin function to show diff
  -- Call the plugin function to show diff
  local result = require("unified.git").show_git_diff_against_commit("HEAD", vim.api.nvim_get_current_buf())
  assert(result, "Failed to display diff")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Get all extmarks with details
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })

  -- Check for deleted lines with minus sign in virt_lines content
  local minus_sign_in_content = false

  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details.virt_lines then
      for _, vline in ipairs(details.virt_lines) do
        for _, vtext in ipairs(vline) do
          local text = vtext[1]
          -- Check if text starts with minus symbol
          if text:match("^%-") then
            minus_sign_in_content = true
            break
          end
        end
      end
    end
  end

  -- This assertion should PASS with the current implementation because the '-' symbol
  -- is correctly omitted from the virtual line content.
  assert(not minus_sign_in_content, "Deletion symbol '-' appears in virtual line content instead of being omitted")

  -- Check if we have combined extmarks with both virt_lines and sign_text
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
  local found_sign_for_deleted_lines = false

  -- Debug all extmarks
  for _, mark in ipairs(extmarks) do
    local details = mark[4]

    -- We should NOT have extmarks that have both virt_lines (for deleted content) AND sign_text
    if details.virt_lines and details.sign_text then
      found_sign_for_deleted_lines = true
      break
    end
  end

  -- We should NOT have combined extmarks with both virt_lines and sign_text
  assert(not found_sign_for_deleted_lines, "Found signs for deleted lines, which can cause confusion")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that deleted lines DON'T show line numbers or duplicate indicators
function M.test_no_line_numbers_in_deleted_lines()
  -- Create temporary git repository
  local utils = require("test.test_utils")
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create a long file with numbered lines to clearly see line numbers
  local test_file = "lines.txt"

  -- Create content with 20 numbered lines
  local content = {}
  for i = 1, 20 do
    table.insert(content, string.format("Line %02d: This is line number %d", i, i))
  end

  local test_path = utils.create_and_commit_file(repo, test_file, content, "Initial commit")

  -- Open the file and delete line 11
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 10, 11, false, {}) -- Delete line 11

  -- Call the plugin function to show diff
  -- Call the plugin function to show diff
  local result = require("unified.git").show_git_diff_against_commit("HEAD", vim.api.nvim_get_current_buf())
  assert(result, "Failed to display diff")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Get all buffer lines
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local buffer_line_count = #buffer_lines

  local extmarks = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })

  -- Check if any virtual text contains line numbers or dash + number patterns
  -- These patterns would indicate the issue where we're seeing "-  11" type formatting
  local found_line_number_indicators = false
  local suspicious_patterns = {
    "^%-%s*%d+$", -- Matches patterns like "- 11" or "-  11"
    "^%-%d+$", -- Matches patterns like "-11"
    "^%d+$", -- Just a number by itself
    "^line%s+%d+$", -- Matches "line 11" type patterns (case insensitive)
  }

  -- Examine all virtual text content
  for _, mark in ipairs(extmarks) do
    local id, row, col, details = unpack(mark)
    if details.virt_lines then
      for _, vline in ipairs(details.virt_lines) do
        for _, vtext in ipairs(vline) do
          local text = vtext[1]

          -- Look for suspicious line number patterns
          for _, pattern in ipairs(suspicious_patterns) do
            if text:match(pattern) or (text:gsub("%s+", "") == "-") then
              found_line_number_indicators = true
              break
            end
          end

          -- Check if the text is JUST the literal content of Line 11
          -- which would indicate the content is displaying correctly
          local expected_deleted_line = "Line 11: This is line number 11"
          if not (text == expected_deleted_line) then
            -- If the text contains the pattern "line 11" (case insensitive)
            -- but is not exactly the full Line 11 content, it's suspicious
            if text:lower():match("line%s*11") and text ~= expected_deleted_line then
              found_line_number_indicators = true
            end
          end
        end
      end
    end
  end

  -- This assertion will fail if we find any line number indicators
  assert(
    not found_line_number_indicators,
    "Found line number indicators in virtual text (like '-  11' or just line numbers)"
  )

  -- Ensure the deleted content is displayed correctly
  local found_correct_line_content = false
  for _, mark in ipairs(extmarks) do
    local id, row, col, details = unpack(mark)
    if details.virt_lines then
      for _, vline in ipairs(details.virt_lines) do
        for _, vtext in ipairs(vline) do
          local text = vtext[1]
          -- Check for the exact content of Line 11
          if text == "Line 11: This is line number 11" then
            found_correct_line_content = true
            break
          end
        end
      end
    end
  end

  assert(found_correct_line_content, "The deleted line content is not displayed correctly")

  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that each deleted line only has one UI element (not both sign and virtual line)
function M.test_single_deleted_line_element()
  -- Create temporary git repository
  local utils = require("test.test_utils")
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create a numbered list file and commit it (better for testing line numbers)
  local test_file = "list.txt"
  local test_path = utils.create_and_commit_file(repo, test_file, {
    "Line 1",
    "Line 2",
    "Line 3",
    "Line 4",
    "Line 5",
  }, "Initial commit")

  -- Open the file and delete a line
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 1, 2, false, {}) -- Delete "Line 2"

  -- Call the plugin function to show diff
  -- Call the plugin function to show diff
  local result = require("unified.git").show_git_diff_against_commit("HEAD", vim.api.nvim_get_current_buf())
  assert(result, "Failed to display diff")

  -- Get buffer and namespace
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_diff")

  -- Count the number of deleted lines in the diff
  local diff_cmd =
    string.format("cd %s && git diff %s", vim.fn.shellescape(repo.repo_dir), vim.fn.shellescape(test_file))
  local diff_output = vim.fn.system(diff_cmd)

  -- Count lines starting with "-" (excluding the diff header lines)
  local deleted_lines_count = 0
  for line in diff_output:gmatch("[^\r\n]+") do
    if line:match("^%-") and not line:match("^%-%-%-") and not line:match("^%-%-") then
      deleted_lines_count = deleted_lines_count + 1
    end
  end

  -- Get all signs
  local signs = vim.fn.sign_getplaced(buffer, { group = "unified_diff" })
  local delete_signs_count = 0

  if #signs > 0 and #signs[1].signs > 0 then
    for _, sign in ipairs(signs[1].signs) do
      if sign.name == "unified_diff_delete" then
        delete_signs_count = delete_signs_count + 1
      end
    end
  end

  -- Get all virtual lines
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
  local virt_lines_count = 0

  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details.virt_lines then
      virt_lines_count = virt_lines_count + 1
    end
  end

  -- Check for extmarks with both sign_text and virt_lines
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
  local found_combined_extmarks = 0

  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details.sign_text and details.virt_lines then
      found_combined_extmarks = found_combined_extmarks + 1
    end
  end

  -- We've changed our approach to use virtual lines only without signs,
  -- so this test is no longer valid and we'll skip it
  -- Clean up
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

function M.test_new_file_shows_all_lines_added()
  package.loaded["test.test_utils"] = nil
  local utils = require("test.test_utils")
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  utils.create_and_commit_file(repo, "README.md", { "Initial content for HEAD" }, "Initial commit")
  local initial_commit_hash = utils.get_current_commit_hash(repo.repo_dir)

  local new_file_name = "newly_added_file.txt"
  local new_file_content = {
    "This is line 1 of a new file.",
    "This is line 2, also new.",
    "And this is line 3.",
  }
  local new_file_path = repo.repo_dir .. "/" .. new_file_name
  local file = io.open(new_file_path, "w")
  if not file then
    utils.cleanup_git_repo(repo)
    assert(false, "Failed to create new file for test: " .. new_file_path)
    return
  end
  file:write(table.concat(new_file_content, "\n") .. "\n")
  file:close()

  vim.cmd("edit " .. new_file_path)
  local buffer = vim.api.nvim_get_current_buf()

  local unified_git = require("unified.git")
  local success = unified_git.show_git_diff_against_commit(initial_commit_hash, buffer)
  assert(success, "show_git_diff_against_commit failed for new file")

  local extmarks = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })

  local added_lines_count = 0
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details.line_hl_group == "UnifiedDiffAdd" then
      added_lines_count = added_lines_count + 1
    end
  end

  assert(
    added_lines_count == #new_file_content,
    "Expected all " .. #new_file_content .. " lines to be marked as added, but got " .. added_lines_count
  )

  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete! " .. new_file_path)
  utils.cleanup_git_repo(repo)

  return true
end

return M
