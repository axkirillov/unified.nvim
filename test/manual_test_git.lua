-- Manual test for unified.nvim with git functionality
--
-- This script sets up a test environment to manually test the git diff
-- functionality of the unified.nvim plugin.
--
-- Instructions:
-- 1. Run this script with Neovim:
--    nvim -u NONE -S test/manual_test_git.lua
--
-- 2. The script will:
--    - Create a temporary git repository
--    - Create a test file and commit it
--    - Make changes to the file to test diff visualization
--
-- 3. Use the provided commands to test the plugin:
--    :UnifiedDiffGit - Show diff against git HEAD
--    :UnifiedDiffBuffer - Show diff against saved file
--    :UnifiedDiffToggle - Toggle diff display
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

  -- Create initial file
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

  -- Commit the file
  system("git add " .. test_file)
  system('git commit -m "Initial commit"')

  -- Open the file in the current buffer
  vim.cmd("edit " .. test_file)

  -- Make some changes to test the diff
  local buffer = vim.api.nvim_get_current_buf()

  -- Change line 3
  vim.api.nvim_buf_set_lines(buffer, 2, 3, false, { "This line has been modified." })

  -- Add a line after line 5
  vim.api.nvim_buf_set_lines(buffer, 5, 5, false, { "This is a new line inserted between lines." })

  -- Delete line 8
  vim.api.nvim_buf_set_lines(buffer, 8, 9, false, {})

  -- Add lines at the end
  vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "", "These lines were added at the end.", "One more new line." })

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
  echo("The following commands are available for testing:")
  echo("  :Unified - Show diff against git HEAD")
  echo("  :Unified toggle - Toggle diff display")
  echo("  :Unified refresh - Force refresh the diff")
  echo("  :Unified commit HEAD - Show diff against HEAD")
  echo("  :Unified commit HEAD~1 - Show diff against the previous commit")
  echo("")
  echo("For quick testing of the commit reference feature, you can use:")
  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")
  local command = string.format("  :Unified commit %s", first_commit)
  echo(command)
  echo("")
  echo("Press q to quit without saving.")
  echo("")
end

-- Run the test setup
setup_test()
