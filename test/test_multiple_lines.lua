-- Test for multiple added lines issue
local M = {}
local utils = require('test.test_utils')

-- Test that multiple added lines are all highlighted properly
function M.test_multiple_added_lines(env)
  -- Setup git repo
  local git_env = utils.setup_git_repo()
  if not git_env then
    return true -- Skip test if git is not available
  end

  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = git_env.repo_dir .. "/" .. test_file
  vim.fn.writefile({ "line 1", "line 2", "line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Initial commit'")

  -- Get the commit hash
  local commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")
  print("Commit: " .. commit)

  -- Open the file and add multiple new lines consecutively
  vim.cmd("edit " .. test_path)
  local buffer = vim.api.nvim_get_current_buf()
  
  -- Add three new lines in a row after line 3
  vim.api.nvim_buf_set_lines(buffer, 3, 3, false, {
    "new line 1", 
    "new line 2", 
    "new line 3"
  })
  
  -- Write the current content
  local buffer_content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  local temp_file = vim.fn.tempname()
  vim.fn.writefile(vim.split(buffer_content, "\n"), temp_file)
  
  print("Modified file content:")
  print(buffer_content)

  -- Get namespace to check for extmarks
  local ns_id = vim.api.nvim_create_namespace("unified_diff")
  
  -- Clear any existing extmarks
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  -- Show diff against HEAD
  local result = require("unified").show_diff("HEAD")
  assert(result, "Failed to display diff")
  
  -- Print buffer content for debugging
  local buffer_content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  print("Buffer content:\n" .. buffer_content)

  -- Get all extmarks with details to check highlights
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
  
  -- Map for checking which lines have been marked with highlights
  local highlighted_lines = {}
  
  -- Process all extmarks and create a map of highlighted lines
  for _, mark in ipairs(extmarks) do
    local row = mark[2]
    local details = mark[4]
    
    -- Check for line highlights (added/modified lines)
    if details.line_hl_group then
      highlighted_lines[row + 1] = details.line_hl_group
    end
    
    -- Also count lines with just sign_text as highlighted
    if details.sign_text and details.sign_text:match("%+") then
      highlighted_lines[row + 1] = "SignHighlighted"
    end
    
    -- For Neovim versions where sign_text might be placed separately
    if details.sign_name and details.sign_name:match("add") then
      highlighted_lines[row + 1] = "SignHighlighted"
    end
  end
  
  -- Debug extmarks
  print("Found " .. #extmarks .. " extmarks")
  for i, mark in ipairs(extmarks) do
    local row = mark[2]
    local details = mark[4]
    print(string.format("Extmark %d: row=%d, details=%s", 
      i, row, vim.inspect(details)))
  end
  
  -- Print buffer lines and highlight status
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  print("Buffer content with highlight status:")
  for i, line in ipairs(buffer_lines) do
    local highlight_status = highlighted_lines[i] and "HIGHLIGHTED" or "NOT HIGHLIGHTED"
    print(string.format("Line %d: '%s' - %s", i, line, highlight_status))
  end
  
  -- Check if all three added lines are highlighted
  local result = true
  if not highlighted_lines[4] then
    print("ERROR: Added line 1 is not highlighted")
    result = false
  end
  
  if not highlighted_lines[5] then
    print("ERROR: Added line 2 is not highlighted")
    result = false
  end
  
  if not highlighted_lines[6] then
    print("ERROR: Added line 3 is not highlighted")
    result = false
  end
  
  -- Clean up
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })
  vim.cmd("bdelete!")
  
  -- Clean up git repo
  utils.teardown_git_repo(git_env)
  
  return result
end

function M.run_tests()
  local env = utils.setup()
  local success = M.test_multiple_added_lines(env)
  utils.teardown(env)
  return success
end

return M