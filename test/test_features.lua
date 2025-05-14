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

  local first_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

  vim.fn.writefile({ "line 1", "modified line 2", "line 3", "line 4", "line 5", "line 6" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  local second_commit = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

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
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Second commit'")

  vim.fn.writefile({ "line 1", "modified line 2", "modified line 3", "line 4", "line 5" }, test_path)
  vim.fn.system("git add " .. test_file)
  vim.fn.system("git commit -m 'Third commit'")

  local first_commit = vim.fn.system("git rev-parse HEAD~2"):gsub("\n", "")
  local _ = vim.fn.system("git rev-parse HEAD~1"):gsub("\n", "")
  local _ = vim.fn.system("git rev-parse HEAD"):gsub("\n", "")

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

  local git_command = string.format(
    "cd %s && git show %s:%s",
    vim.fn.shellescape(repo.repo_dir),
    vim.fn.shellescape(first_commit),
    vim.fn.shellescape(test_file)
  )
  local first_commit_content = vim.fn.system(git_command)

  git_command =
    string.format("cd %s && git show HEAD:%s", vim.fn.shellescape(repo.repo_dir), vim.fn.shellescape(test_file))
  local head_content = vim.fn.system(git_command)

  local temp_current = vim.fn.tempname()
  local temp_first = vim.fn.tempname()
  local temp_head = vim.fn.tempname()

  vim.fn.writefile(vim.split(current_file_content, "\n"), temp_current)
  vim.fn.writefile(vim.split(first_commit_content, "\n"), temp_first)
  vim.fn.writefile(vim.split(head_content, "\n"), temp_head)

  local diff_first_cmd = string.format("diff -u %s %s", temp_first, temp_current)
  local diff_head_cmd = string.format("diff -u %s %s", temp_head, temp_current)

  local diff_first_output = vim.fn.system(diff_first_cmd)
  local diff_head_output = vim.fn.system(diff_head_cmd)

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

return M
