-- Test utilities for unified.nvim
local M = {}

-- Setup test environment
function M.setup()
  -- Create temporary test file
  local test_file = vim.fn.tempname()
  vim.fn.writefile({ "line 1", "line 2", "line 3", "line 4", "line 5" }, test_file)

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
    test_file = test_file,
  }
end

-- Cleanup test environment
function M.teardown(env)
  vim.fn.delete(env.test_file)
end

-- Setup git repository for testing
function M.setup_git_repo()
  -- Skip test if git is not available
  local git_version = vim.fn.system("git --version")
  if vim.v.shell_error ~= 0 then
    print("Git not available, skipping git diff test")
    return nil
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

  return {
    repo_dir = repo_dir,
    old_dir = old_dir
  }
end

-- Cleanup git repository
function M.teardown_git_repo(git_env)
  if not git_env then
    return
  end
  
  -- Return to original directory
  vim.cmd("cd " .. git_env.old_dir)
  
  -- Clean up git repo
  vim.fn.delete(git_env.repo_dir, "rf")
end

return M