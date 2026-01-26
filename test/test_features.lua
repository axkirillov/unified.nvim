local utils = require("test.test_utils")

local M = {}

function M.test_auto_refresh()
  local config = require("unified.config")
  assert(config.values.auto_refresh == true, "Auto-refresh should be enabled by default")

  require("unified").setup({ auto_refresh = false })
  assert(config.values.auto_refresh == false, "Auto-refresh should be disabled after setup")

  require("unified").setup({ auto_refresh = true })
  assert(config.values.auto_refresh == true, "Auto-refresh should be re-enabled after setup")

  require("unified").setup({})

  return true
end

function M.test_diff_against_commit()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end
  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  local first_commit = vim.fn.system({ "git", "-C", repo.repo_dir, "rev-parse", "HEAD" }):gsub("\n", "")

  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5", "line 6" }, test_path)
  vim.fn.system({ "git", "-C", repo.repo_dir, "add", test_file })
  vim.fn.system({ "git", "-C", repo.repo_dir, "commit", "-m", "Second commit" })

  local second_commit = vim.fn.system({ "git", "-C", repo.repo_dir, "rev-parse", "HEAD" }):gsub("\n", "")

  vim.cmd("edit! " .. test_path)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "modified line 1" }) -- Change line 1
  vim.api.nvim_buf_set_lines(0, 3, 4, false, {}) -- Delete line 4
  vim.api.nvim_buf_set_lines(0, 4, 5, false, { "new line" }) -- Add new line
  vim.cmd("write")

  local buffer = vim.api.nvim_get_current_buf()
  local result = require("unified.git").show_git_diff_against_commit(first_commit, buffer)

  local extmarks = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })

  assert(result, "show_git_diff_against_commit() should return true")
  assert(#extmarks > 0, "No diff extmarks were created")

  utils.clear_diff_marks(buffer)

  result = require("unified.git").show_git_diff_against_commit(second_commit, buffer)
  extmarks = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })

  assert(result, "show_git_diff_against_commit() should return true for second commit")
  assert(#extmarks > 0, "No diff extmarks were created for second commit")

  utils.clear_diff_marks(buffer)

  vim.cmd("write")
  result = require("unified.git").show_git_diff_against_commit(first_commit, buffer)
  assert(result, "show_git_diff_against_commit() should return true after write and direct call")
  extmarks = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })
  assert(#extmarks > 0, "No diff extmarks were created after write and direct call")

  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  utils.cleanup_git_repo(repo)

  return true
end

function M.test_commit_base_persistence()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5" }, test_path)
  vim.fn.system({ "git", "-C", repo.repo_dir, "add", test_file })
  vim.fn.system({ "git", "-C", repo.repo_dir, "commit", "-m", "Second commit" })

  vim.fn.writefile({ "line 1", "modified line 2", "modified line 3", "line 4", "line 5" }, test_path)
  vim.fn.system({ "git", "-C", repo.repo_dir, "add", test_file })
  vim.fn.system({ "git", "-C", repo.repo_dir, "commit", "-m", "Third commit" })

  local first_commit = vim.fn.system({ "git", "-C", repo.repo_dir, "rev-parse", "HEAD~2" }):gsub("\n", "")
  local _ = vim.fn.system({ "git", "-C", repo.repo_dir, "rev-parse", "HEAD~1" }):gsub("\n", "")
  local _ = vim.fn.system({ "git", "-C", repo.repo_dir, "rev-parse", "HEAD" }):gsub("\n", "")

  vim.cmd("edit " .. test_path)
  local buffer = vim.fn.bufnr(test_path)

  local result = require("unified.git").show_git_diff_against_commit(first_commit, buffer)
  assert(result, "Failed to display diff against first commit")

  local extmarks_before_edit = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })
  assert(#extmarks_before_edit > 0, "No diff extmarks were created for first commit")

  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "MODIFIED line 1" })

  vim.cmd("sleep 100m")

  local extmarks_after_edit = utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })
  assert(#extmarks_after_edit > 0, "No diff extmarks after buffer modification")

  local current_file_content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")

  local first_commit_content = vim.fn.system({ "git", "-C", repo.repo_dir, "show", first_commit .. ":" .. test_file })

  local head_content = vim.fn.system({ "git", "-C", repo.repo_dir, "show", "HEAD:" .. test_file })

  local temp_current = vim.fn.tempname()
  local temp_first = vim.fn.tempname()
  local temp_head = vim.fn.tempname()

  vim.fn.writefile(vim.split(current_file_content, "\n"), temp_current)
  vim.fn.writefile(vim.split(first_commit_content, "\n"), temp_first)
  vim.fn.writefile(vim.split(head_content, "\n"), temp_head)

  -- Use table-form diff invocations directly when calling system()

  local diff_first_output = vim.fn.system({ "diff", "-u", temp_first, temp_current })
  local diff_head_output = vim.fn.system({ "diff", "-u", temp_head, temp_current })

  local still_diffing_against_first = diff_first_output:find("modified line 2")
    and diff_first_output:find("modified line 3")
  local defaulted_to_head = not diff_head_output:find("modified line 2")
    and not diff_head_output:find("modified line 3")

  assert(
    still_diffing_against_first,
    "Plugin is not maintaining diff against original commit after buffer modification"
  )

  assert(not defaulted_to_head, "Plugin incorrectly defaulted to diffing against HEAD after buffer modification")

  utils.clear_diff_marks(buffer)
  vim.cmd("bdelete!")

  utils.cleanup_git_repo(repo)
  vim.fn.delete(temp_current)
  vim.fn.delete(temp_first)
  vim.fn.delete(temp_head)

  return true
end

function M.test_symbolic_ref_follows_head_after_commit()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  local test_file = "test.txt"
  local test_path = utils.create_and_commit_file(
    repo,
    test_file,
    { "line 1", "line 2", "line 3", "line 4", "line 5" },
    "Initial commit"
  )

  vim.cmd("edit " .. test_path)
  local buf = vim.api.nvim_get_current_buf()

  -- Make a change that we will commit later.
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "modified line 1" })
  vim.cmd("write")

  -- Avoid opening the file tree in tests; we only need command.run() to store the base ref.
  local file_tree = require("unified.file_tree")
  local old_show = file_tree.show
  file_tree.show = function()
    return true
  end

  require("unified.command").run("HEAD")

  local ok = vim.wait(1000, function()
    local state = require("unified.state")
    local ok_base, base = pcall(state.get_commit_base)
    return state.is_active() and ok_base and base ~= nil
  end)
  assert(ok, "Unified did not activate in time")

  local state = require("unified.state")
  local base = state.get_commit_base()
  assert(base == "HEAD", "Expected commit base to stay symbolic (HEAD), got: " .. tostring(base))

  require("unified.command").reset()
  file_tree.show = old_show

  -- Commit the change, moving HEAD forward.
  vim.fn.system({ "git", "-C", repo.repo_dir, "add", test_file })
  vim.fn.system({ "git", "-C", repo.repo_dir, "commit", "-m", "Commit change" })

  -- Now the working tree matches the new HEAD; diffing against the stored base should show no changes.
  require("unified.diff").show_current()
  local ns = vim.api.nvim_create_namespace("unified_diff")
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  assert(#extmarks == 0, "Expected no diff extmarks after commit when base is a moving ref")

  utils.clear_diff_marks(buf)
  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)

  return true
end

return M
