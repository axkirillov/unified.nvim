-- Test file for unified.nvim commit functionality
local M = {}

-- Import test utilities
local utils = require("test.test_utils")

-- Test that 'Unified commit HEAD~1' doesn't produce error messages
function M.test_unified_commit_no_errors()
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

  -- Make changes and create a second commit
  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  -- Open the file
  vim.cmd("edit " .. test_path)

  -- Make additional changes for diffing
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { "further modified line 2" })

  -- Mock the nvim_echo function to capture error messages
  local old_nvim_echo = vim.api.nvim_echo
  local error_messages = {}
  vim.api.nvim_echo = function(chunks, history, opts)
    for _, chunk in ipairs(chunks) do
      local text, hl_group = chunk[1], chunk[2]
      if hl_group == "ErrorMsg" then
        table.insert(error_messages, text)
      end
    end
  end

  -- Run the Unified commit command
  vim.cmd("Unified commit HEAD~1")

  -- Restore the original nvim_echo function
  vim.api.nvim_echo = old_nvim_echo

  -- Check that no error messages were produced
  assert(#error_messages == 0, "Unified commit HEAD~1 produced error messages: " .. table.concat(error_messages, ", "))

  -- Verify that we have extmarks showing the diff (indicating success)
  local buffer = vim.api.nvim_get_current_buf()
  local has_extmarks, marks = utils.check_extmarks_exist(buffer)
  assert(has_extmarks, "No diff extmarks were created after running Unified commit HEAD~1")

  -- Also check the global state is properly set
  local state = require("unified.state")
  assert(state.is_active, "Unified plugin should be active after running Unified commit HEAD~1")
  assert(state.commit_base == "HEAD~1", "Commit base should be set to HEAD~1")

  -- Clean up
  -- First properly deactivate the plugin
  local unified = require("unified")
  unified.deactivate()

  -- After deactivating, we can safely delete the buffer
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

-- Test that 'Unified commit HEAD~1' handles empty buffer gracefully
function M.test_unified_commit_empty_buffer()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create initial file and commit it
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(repo, test_file, { "line 1", "line 2", "line 3" }, "Initial commit")

  -- Make changes and create a second commit
  vim.fn.writefile({ "line 1", "modified line 2", "line 3" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  -- Do NOT open any file - test on a fresh buffer
  vim.cmd("enew")

  -- Mock the nvim_echo function to capture all messages
  local old_nvim_echo = vim.api.nvim_echo
  local error_messages = {}
  local normal_messages = {}

  vim.api.nvim_echo = function(chunks, history, opts)
    for _, chunk in ipairs(chunks) do
      local text, hl_group = chunk[1], chunk[2]
      if hl_group == "ErrorMsg" then
        table.insert(error_messages, text)
      else
        table.insert(normal_messages, text)
      end

      -- Print captured message for debugging
      print(string.format("Message: '%s' with highlight: '%s'", text, hl_group or "Normal"))
    end
  end

  -- Set current directory to the test repo to ensure git commands work
  vim.cmd("cd " .. repo.repo_dir)

  -- Run the Unified commit command
  local success, error_msg = pcall(function()
    vim.cmd("Unified commit HEAD~1")
  end)

  -- Restore the original nvim_echo function
  vim.api.nvim_echo = old_nvim_echo

  -- Check that the command didn't crash
  assert(success, "Unified commit HEAD~1 crashed with error: " .. tostring(error_msg))

  -- Shouldn't have any error messages now with our new implementation
  assert(#error_messages == 0, "Expected no error messages, but got: " .. table.concat(error_messages, ", "))

  -- Should have a message about activating the file tree instead
  local expected_message_found = false
  for _, msg in ipairs(normal_messages) do
    if msg:match("Activated file tree with commit base") then
      expected_message_found = true
      break
    end
  end

  assert(expected_message_found, "Expected message about activating file tree with commit base, but didn't find it")

  -- Also check the global state is properly set
  local state = require("unified.state")
  assert(state.is_active, "Unified plugin should be active after command")
  assert(state.commit_base == "HEAD~1", "Commit base should be set to HEAD~1")

  -- Show all collected messages for debugging
  print("Error messages: " .. table.concat(error_messages, ", "))
  print("Normal messages: " .. table.concat(normal_messages, ", "))

  -- Clean up
  -- First properly deactivate the plugin
  local unified = require("unified")
  unified.deactivate()

  -- After deactivating, we can safely delete the buffer
  local buffer = vim.api.nvim_get_current_buf()
  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  -- Clean up git repo
  utils.cleanup_git_repo(repo)

  return true
end

return M
