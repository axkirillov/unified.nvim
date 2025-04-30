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

-- Shared repository for testing
M.shared_git_repo = nil
M.shared_repo_in_use = false

-- Create a shared Git repository if one doesn't exist yet
function M.init_shared_git_repo()
  if M.shared_git_repo then
    return M.shared_git_repo
  end

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

  -- Create an empty base commit
  vim.fn.system("git commit --allow-empty -m 'Base commit'")

  M.shared_git_repo = {
    repo_dir = repo_dir,
    old_dir = old_dir,
  }

  return M.shared_git_repo
end

-- Reset the shared git repository to a clean state
function M.reset_git_repo(repo)
  if not repo then
    return false
  end

  -- Return to the repo directory
  vim.cmd("cd " .. repo.repo_dir)

  -- Clean up all changes and go back to base commit
  vim.fn.system("git checkout main 2>/dev/null || git checkout master 2>/dev/null")
  vim.fn.system("git branch | grep -v '\\*' | xargs git branch -D 2>/dev/null") -- Delete all other branches
  vim.fn.system("git reset --hard HEAD") -- Reset to HEAD
  vim.fn.system("git clean -fdx") -- Clean all untracked files and directories

  return true
end

-- Create a test branch for isolation
function M.create_test_branch(repo, branch_name)
  if not repo then
    return false
  end

  branch_name = branch_name or ("test_branch_" .. os.time())
  vim.fn.system("git checkout -b " .. branch_name)
  return branch_name
end

-- Create a temporary git repository for testing (legacy method for backward compatibility)
function M.create_git_repo()
  -- Check if we should use the shared repo
  if vim.env.UNIFIED_USE_SHARED_REPO == "1" then
    if M.shared_repo_in_use then
      -- If the shared repo is in use, create a new temporary repo
      return M.create_temp_git_repo()
    end

    -- Initialize or get the shared repo
    local repo = M.init_shared_git_repo()
    if not repo then
      return nil
    end

    -- Reset the repo to clean state
    M.reset_git_repo(repo)

    -- Create a test branch
    M.create_test_branch(repo)

    -- Mark as in use
    M.shared_repo_in_use = true

    return repo
  else
    -- Fall back to creating a new temporary repo
    return M.create_temp_git_repo()
  end
end

-- Create a disposable git repository for testing
function M.create_temp_git_repo()
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
    is_temp = true,
  }
end

-- Clean up a test git repository
function M.cleanup_git_repo(repo)
  if not repo then
    return
  end

  -- Return to original directory
  vim.cmd("cd " .. repo.old_dir)

  -- For shared repo, just mark as no longer in use
  if not repo.is_temp and vim.env.UNIFIED_USE_SHARED_REPO == "1" then
    M.shared_repo_in_use = false
    return
  end

  -- Clean up git repo only for temporary repos
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

local function wait_until(fn, timeout)
  timeout = timeout or 1000
  local start = vim.loop.hrtime()
  while vim.loop.hrtime() - start < timeout * 1e6 do
    if fn() then
      return true
    end
    vim.wait(20, function() end, 1, false)
  end
  return fn()
end

function M.check_extmarks_exist(buffer, namespace, timeout)
  local ns = vim.api.nvim_create_namespace(namespace or "unified_diff")
  local marks = {}
  local found = wait_until(function()
    marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
    return #marks > 0
  end, timeout)
  return found, marks
end

function M.get_extmarks(buffer, opts)
  opts = opts or {}
  local ns = vim.api.nvim_create_namespace(opts.namespace or "unified_diff")
  local ext = {}
  wait_until(function()
    ext = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, opts.details == false and {} or { details = true })
    return #ext > 0
  end, opts.timeout or 1000)
  return ext
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
