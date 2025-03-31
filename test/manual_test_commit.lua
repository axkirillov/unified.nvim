-- Manual test for unified.nvim with commit functionality
--
-- This script sets up a test environment to manually test the `Unified commit HEAD~1`
-- functionality of the unified.nvim plugin.
--
-- Instructions:
-- 1. Run this script with Neovim:
--    nvim -u NONE -c "set rtp+=." -c "luafile test/manual_test_commit.lua"
--
-- 2. The script will:
--    - Create a temporary git repository
--    - Create a test file and make multiple commits
--    - Make changes to the file to test diff visualization against various commits
--
-- 3. Use the provided commands to test the plugin:
--    :Unified commit HEAD - Show diff against current commit
--    :Unified commit HEAD~1 - Show diff against previous commit
--    :Unified commit HEAD~2 - Show diff against two commits ago (if available)
--
-- 4. Press 'q' to quit without saving changes

-- Helper functions
local function echo(msg)
  vim.cmd('echo "' .. msg:gsub('"', '\\"') .. '"')
end

local function system(cmd)
  return vim.fn.system(cmd)
end

-- Set up test environment
local function setup_test()
  -- Create temporary directory for test
  local temp_dir = vim.fn.tempname()
  system("mkdir -p " .. temp_dir)
  vim.cmd("cd " .. temp_dir)

  -- Initialize git repo
  system("git init")
  system('git config user.name "Test User"')
  system('git config user.email "test@example.com"')

  -- Create initial file and commit (Commit 1)
  local initial_content = {
    "# Test File for unified.nvim",
    "",
    "This is line 1 of the test file.",
    "This is line 2 of the test file.",
    "This is line 3 of the test file.",
    "This is line 4 of the test file.",
    "This is line 5 of the test file.",
    "",
    "## Section",
    "",
    "More content here.",
    "And some more here.",
    "Final line.",
  }

  local test_file = "test_file.md"
  vim.fn.writefile(initial_content, test_file)

  -- Commit the file (Commit 1)
  system("git add " .. test_file)
  system('git commit -m "Initial commit"')
  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  -- Make first modifications and commit (Commit 2)
  local second_content = {
    "# Test File for unified.nvim",
    "",
    "This is line 1 of the test file.",
    "This is line 2 modified.", -- Modified line
    "This is line 3 of the test file.",
    "This is line 4 of the test file.",
    "This is line 5 of the test file.",
    "",
    "## Updated Section", -- Modified line
    "",
    "More content here.",
    "And some more here.",
    "Additional line.", -- Added line
    "Final line.",
  }
  vim.fn.writefile(second_content, test_file)
  system("git add " .. test_file)
  system('git commit -m "Second commit with modifications"')
  local second_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  -- Make second modifications and commit (Commit 3)
  local third_content = {
    "# Test File for unified.nvim - Updated", -- Modified line
    "",
    "This is line 1 of the test file.",
    "This is line 2 modified.",
    "This is line 3 of the test file.",
    "This is line 4 of the test file.",
    "This is line 5 of the test file.",
    "",
    "## Updated Section",
    "",
    "More content here with changes.", -- Modified line
    "And some more here.",
    "Additional line.",
    "Final line with updates.", -- Modified line
  }
  vim.fn.writefile(third_content, test_file)
  system("git add " .. test_file)
  system('git commit -m "Third commit with more modifications"')
  local third_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  -- Open the file in the current buffer
  vim.cmd("edit " .. test_file)

  -- Make more changes to test diffing against different commits
  local buffer = vim.api.nvim_get_current_buf()

  -- Change several lines to create interesting diffs
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "# Test File for unified.nvim - CURRENT CHANGES" })
  vim.api.nvim_buf_set_lines(buffer, 4, 5, false, { "This is line 3 with CURRENT changes." })
  vim.api.nvim_buf_set_lines(buffer, 7, 8, false, {}) -- Delete a line
  vim.api.nvim_buf_set_lines(buffer, 9, 10, false, { "NEW LINE IN CURRENT CHANGES", "" }) -- Add a line
  vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "", "This is a completely new line at the end." })

  -- Set up additional key mappings for testing
  vim.api.nvim_set_keymap("n", "q", ":q!<CR>", { noremap = true })

  -- Set up the plugin
  require("unified").setup({
    default_diff_mode = "git", -- Set to use git diff by default
  })

  -- Display instructions
  echo("")
  echo("== Test Environment Setup Complete ==")
  echo("")
  echo("This buffer contains a modified version of a file that has been committed to git.")
  echo("Three commits have been made, and there are additional uncommitted changes.")
  echo("")
  echo("The following commands are available for testing:")
  echo("  :Unified - Show diff against git HEAD (latest commit)")
  echo("  :Unified commit HEAD - Show diff against latest commit")
  echo("  :Unified commit HEAD~1 - Show diff against previous commit (2nd commit)")
  echo("  :Unified commit HEAD~2 - Show diff against first commit")
  echo("")
  echo("For testing with specific commit hashes:")
  echo(string.format("  :Unified commit %s  # First commit", first_commit:sub(1, 8)))
  echo(string.format("  :Unified commit %s  # Second commit", second_commit:sub(1, 8)))
  echo(string.format("  :Unified commit %s  # Third commit", third_commit:sub(1, 8)))
  echo("")
  echo("Note: Tab completion should work with :Unified commit <Tab>")
  echo("")
  echo("Press q to quit without saving.")
  echo("")
end

-- Run the test setup
setup_test()
