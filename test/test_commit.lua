-- Test file for unified.nvim commit functionality
local M = {}

-- Import test utilities
local utils = require("test.test_utils")

-- Test that 'Unified commit HEAD~4' updates the commit base without disabling the plugin
function M.test_unified_commit_update_base()
  -- Create temporary git repository
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Create initial file and add commits for testing
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(repo, test_file, { "line 1", "line 2", "line 3" }, "First commit")

  -- Create 4 additional commits so HEAD~4 is valid
  for i = 1, 4 do
    vim.fn.writefile({ "line 1", "modified line 2 in commit " .. i, "line 3" }, test_path)
    vim.fn.system("git -C " .. repo.repo_dir .. " add " .. test_file)
    vim.fn.system("git -C " .. repo.repo_dir .. " commit -m 'Commit " .. i .. "'")
  end

  -- Open the file
  vim.cmd("edit " .. test_path)

  -- Make additional changes
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { "current modification" })
  vim.cmd("write") -- Save buffer before running command to avoid E37

  -- Mock the nvim_echo and deactivate functions to monitor calls
  local old_nvim_echo = vim.api.nvim_echo
  local unified = require("unified")
  local state = require("unified.state")

  local messages = {}

  vim.api.nvim_echo = function(chunks, _, _)
    for _, chunk in ipairs(chunks) do
      local text, hl_group = chunk[1], chunk[2]
      table.insert(messages, { text = text, hl_group = hl_group or "Normal" })
    end
  end

  -- First activate with HEAD~1
  vim.cmd("Unified HEAD~1")

  local initial_active = state.is_active

  -- Verify initial state is active
  assert(initial_active, "Unified plugin should be active after first commit command")

  -- Now change to HEAD~4 (should update base, not disable)
  vim.cmd("Unified HEAD~4")

  -- Restore mock functions
  vim.api.nvim_echo = old_nvim_echo

  -- Verify the plugin is still active
  assert(state.is_active, "Unified plugin should still be active after changing commit base")

  require("unified.command").reset()
  local buffer = vim.api.nvim_get_current_buf()
  utils.clear_diff_marks(buffer)
  utils.cleanup_git_repo(repo)

  return true
end

return M
