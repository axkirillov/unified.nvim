-- Test file for unified.nvim
local M = {}
-- Expose the module globally for testing
_G.test_unified = M

-- Setup test environment
function M.setup()
  -- Create temporary test file
  local test_file = vim.fn.tempname()
  vim.fn.writefile({'line 1', 'line 2', 'line 3', 'line 4', 'line 5'}, test_file)
  
  -- Define signs in case they aren't loaded from plugin
  vim.fn.sign_define("unified_diff_add", {
    text = "+",
    texthl = "DiffAdd",
  })
  
  vim.fn.sign_define("unified_diff_delete", {
    text = "-",
    texthl = "DiffDelete",
  })
  
  vim.fn.sign_define("unified_diff_change", {
    text = "~",
    texthl = "DiffChange",
  })
  
  return {
    test_file = test_file
  }
end

-- Cleanup test environment
function M.teardown(env)
  vim.fn.delete(env.test_file)
end

-- Test showing diff directly through API
function M.test_show_diff_api(env)
  -- Open test file
  vim.cmd('edit ' .. env.test_file)
  
  -- Make some changes to the buffer
  vim.api.nvim_buf_set_lines(0, 0, 1, false, {'modified line 1'})  -- Change line 1
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {})                   -- Delete line 3
  vim.api.nvim_buf_set_lines(0, 3, 3, false, {'new line'})         -- Add new line
  
  -- Call the plugin function to show diff
  local result = require('unified').show_buffer_diff()
  
  -- Get namespace to check if extmarks exist
  local ns_id = vim.api.nvim_create_namespace('unified_diff')
  local buffer = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  
  -- Check that extmarks were created
  assert(result, "show_buffer_diff() should return true")
  assert(#marks > 0, "No diff extmarks were created")
  
  -- Check for signs
  local signs = vim.fn.sign_getplaced(buffer, {group = "unified_diff"})
  assert(#signs > 0 and #signs[1].signs > 0, "No diff signs were placed")
  
  -- Clear diff
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", {buffer = buffer})
  
  -- Close the buffer
  vim.cmd('bdelete!')
  return true
end

-- Test using the user command
function M.test_diff_command(env)
  -- Open test file
  vim.cmd('edit ' .. env.test_file)
  
  -- Make some changes to the buffer
  vim.api.nvim_buf_set_lines(0, 0, 1, false, {'modified line 1'})  -- Change line 1
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {})                   -- Delete line 3
  vim.api.nvim_buf_set_lines(0, 3, 3, false, {'new line'})         -- Add new line
  
  -- Write changes to diagnose if diff system is working
  local debug_file = vim.fn.tempname()
  vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), debug_file)
  
  -- Log diff command output for debugging
  local diff_cmd = string.format("diff -u %s %s", env.test_file, debug_file)
  local diff_output = vim.fn.system(diff_cmd)
  print("Debug diff output: " .. diff_output)
  
  -- Use user command to show diff
  vim.cmd('UnifiedDiffShow')
  
  -- Get namespace to check if extmarks exist
  local ns_id = vim.api.nvim_create_namespace('unified_diff')
  local buffer = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  
  -- Check that extmarks were created
  assert(#marks > 0, "No diff extmarks were created after running UnifiedDiffShow command")
  
  -- Check for signs
  local signs = vim.fn.sign_getplaced(buffer, {group = "unified_diff"})
  assert(#signs > 0 and #signs[1].signs > 0, "No diff signs were placed after running UnifiedDiffShow command")
  
  -- Validate specific locations
  local found_line1_change = false
  local found_deletion = false
  local found_addition = false
  
  for _, mark in ipairs(marks) do
    local row = mark[2]
    if row == 0 then  -- First line should have a change
      found_line1_change = true
    elseif row == 2 then  -- Line 3 was deleted, should have extmark at line 2
      found_deletion = true
    elseif row == 3 then  -- New line was added at line 4
      found_addition = true
    end
  end
  
  assert(found_line1_change, "No extmark found for changed first line")
  assert(found_deletion, "No extmark found for deleted third line")
  assert(found_addition, "No extmark found for added new line")
  
  -- Use command to toggle diff off
  vim.cmd('UnifiedDiffToggle')
  marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  assert(#marks == 0, "Extmarks were not cleared after toggle command")
  
  -- Clean up debug file
  vim.fn.delete(debug_file)
  
  -- Close the buffer
  vim.cmd('bdelete!')
  return true
end

-- Debug function to test diff parsing
function M.test_diff_parsing(env)
  -- Create two files with known differences
  local file1 = vim.fn.tempname()
  local file2 = vim.fn.tempname()
  
  vim.fn.writefile({'line 1', 'line 2', 'line 3', 'line 4', 'line 5'}, file1)
  vim.fn.writefile({'modified line 1', 'line 2', 'line 4', 'new line', 'line 5'}, file2)
  
  -- Generate diff
  local diff_cmd = string.format("diff -u %s %s", file1, file2)
  local diff_output = vim.fn.system(diff_cmd)
  
  -- Parse the diff
  local hunks = require('unified').parse_diff(diff_output)
  
  -- Verify hunks were correctly parsed
  assert(#hunks > 0, "No hunks were parsed from diff output")
  
  -- Print diff info for debugging
  for i, hunk in ipairs(hunks) do
    print(string.format("Hunk %d: old_start=%d, old_count=%d, new_start=%d, new_count=%d", 
      i, hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count))
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
function M.test_git_diff(env)
  -- Skip test if git is not available
  local git_version = vim.fn.system("git --version")
  if vim.v.shell_error ~= 0 then
    print("Git not available, skipping git diff test")
    return true
  end
  
  -- Create temporary git repository
  local repo_dir = vim.fn.tempname()
  vim.fn.mkdir(repo_dir, "p")
  
  -- Change to repo directory
  local old_dir = vim.fn.getcwd()
  vim.cmd("cd " .. repo_dir)
  
  -- Initialize git repo
  vim.fn.system("git init")
  vim.fn.system("git config user.name 'Test User'")
  vim.fn.system("git config user.email 'test@example.com'")
  
  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = repo_dir .. "/" .. test_file
  vim.fn.writefile({'line 1', 'line 2', 'line 3', 'line 4', 'line 5'}, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Initial commit'")
  
  -- Open the file and make changes
  vim.cmd("edit " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, {'modified line 1'})  -- Change line 1
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {})                   -- Delete line 3
  vim.api.nvim_buf_set_lines(0, 3, 3, false, {'new line'})         -- Add new line
  
  -- Call the plugin function to show git diff
  local result = require('unified').show_git_diff()
  
  -- Get namespace to check if extmarks exist
  local ns_id = vim.api.nvim_create_namespace('unified_diff')
  local buffer = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  
  -- Check that extmarks were created
  assert(result, "show_git_diff() should return true")
  assert(#marks > 0, "No diff extmarks were created")
  
  -- Check for signs
  local signs = vim.fn.sign_getplaced(buffer, {group = "unified_diff"})
  assert(#signs > 0 and #signs[1].signs > 0, "No diff signs were placed")
  
  -- Clear diff
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", {buffer = buffer})
  
  -- Close the buffer
  vim.cmd('bdelete!')
  
  -- Return to original directory
  vim.cmd("cd " .. old_dir)
  
  -- Clean up git repo
  vim.fn.delete(repo_dir, "rf")
  
  return true
end

-- Run all tests
function M.run_tests()
  local env = M.setup()
  local results = {}
  
  -- Initialize unified plugin
  require('unified').setup()
  
  -- Run tests
  local tests = {
    "test_show_diff_api",
    "test_diff_command",
    "test_diff_parsing",
    "test_git_diff"
  }
  
  for _, test_name in ipairs(tests) do
    print("\nRunning " .. test_name)
    local status, err = pcall(function() return M[test_name](env) end)
    table.insert(results, {
      name = test_name,
      status = status,
      error = not status and err or nil
    })
  end
  
  -- Cleanup
  M.teardown(env)
  
  -- Print results
  print("\nTest Results:")
  for _, result in ipairs(results) do
    print(string.format("%s: %s", result.name, result.status and "PASS" or "FAIL"))
    if result.error then
      print("  Error: " .. tostring(result.error))
    end
  end
  
  -- Exit with proper status code
  local all_passed = true
  for _, result in ipairs(results) do
    if not result.status then
      all_passed = false
      break
    end
  end
  
  return all_passed
end

return M