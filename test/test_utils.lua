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

-- Create a temporary git repository for testing
function M.create_git_repo()
  -- Skip test if git is not available
  local git_version = vim.fn.system("git --version")
  if vim.v.shell_error ~= 0 then
    print("Git not available, skipping git diff test")
    return nil
  end

  -- Create temporary git repository
  local repo_dir = vim.fn.tempname()
  vim.fn.mkdir(repo_dir, "p")

  -- Save original directory
  local old_dir = vim.fn.getcwd()
  vim.cmd("cd " .. repo_dir)

  -- Initialize git repo
  vim.fn.system("git init")
  vim.fn.system("git config user.name 'Test User'")
  vim.fn.system("git config user.email 'test@example.com'")

  return {
    repo_dir = repo_dir,
    old_dir = old_dir,
  }
end

-- Clean up a test git repository
function M.cleanup_git_repo(repo)
  if not repo then
    return
  end

  -- Return to original directory
  vim.cmd("cd " .. repo.old_dir)

  -- Clean up git repo
  vim.fn.delete(repo.repo_dir, "rf")
end

-- Helper to create and commit a file in a git repo
function M.create_and_commit_file(repo, filename, content, commit_message)
  local file_path = repo.repo_dir .. "/" .. filename
  vim.fn.writefile(content, file_path)
  vim.fn.system("git add " .. filename)
  vim.fn.system("git commit -m '" .. (commit_message or "Add file") .. "'")
  return file_path
end

-- Helper to modify and commit a file in a git repo
function M.modify_and_commit_file(repo, filename, content, commit_message)
  local file_path = repo.repo_dir .. "/" .. filename
  vim.fn.writefile(content, file_path)
  vim.fn.system("cd " .. repo.repo_dir .. " && git add " .. filename)
  vim.fn.system("cd " .. repo.repo_dir .. " && git commit -m '" .. (commit_message or "Modify file") .. "'")
  return file_path
end

-- Helper to check if extmarks exist
function M.check_extmarks_exist(buffer, namespace)
  local ns_id = vim.api.nvim_create_namespace(namespace or "unified_diff")
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  return #marks > 0, marks
end

-- Helper to check if signs exist
function M.check_signs_exist(buffer, group)
  local signs = vim.fn.sign_getplaced(buffer, { group = group or "unified_diff" })
  return #signs > 0 and #signs[1].signs > 0, signs
end

-- Helper to clean up diff marks
function M.clear_diff_marks(buffer)
  local ns_id = vim.api.nvim_create_namespace("unified_diff")
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })
end

return M
