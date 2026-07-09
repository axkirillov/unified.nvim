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

-- Regression: `auto_refresh = false` must make auto_refresh.setup a no-op
-- (previously the config value was never consulted).
function M.test_auto_refresh_disabled_is_noop()
  local state = require("unified.state")
  local auto_refresh = require("unified.auto_refresh")

  if state.auto_refresh_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  require("unified").setup({ auto_refresh = false })

  local buf = vim.api.nvim_create_buf(false, true)
  auto_refresh.setup(buf)

  assert(state.auto_refresh_augroup == nil, "Disabled auto-refresh must not create an augroup")

  vim.api.nvim_buf_delete(buf, { force = true })
  require("unified").setup({})
  return true
end

-- Regression: each opened buffer keeps its own refresh autocmd (the old
-- clear=true wipe meant only the last buffer refreshed), the augroup id is
-- stored for teardown, and re-running setup does not duplicate autocmds.
function M.test_auto_refresh_registers_per_buffer()
  local state = require("unified.state")
  local auto_refresh = require("unified.auto_refresh")

  if state.auto_refresh_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  require("unified").setup({ auto_refresh = true })

  local buf1 = vim.api.nvim_create_buf(false, true)
  local buf2 = vim.api.nvim_create_buf(false, true)

  auto_refresh.setup(buf1)
  assert(state.auto_refresh_augroup ~= nil, "Enabled auto-refresh must store the augroup id for teardown")
  local group = state.auto_refresh_augroup

  auto_refresh.setup(buf2)
  assert(state.auto_refresh_augroup == group, "Augroup id must remain stable across setups")

  local au1 = vim.api.nvim_get_autocmds({ group = group, buffer = buf1 })
  local au2 = vim.api.nvim_get_autocmds({ group = group, buffer = buf2 })
  assert(#au1 > 0, "buf1 must keep its autocmd after buf2 is set up")
  assert(#au2 > 0, "buf2 must have its own autocmd")

  auto_refresh.setup(buf1)
  local au1_again = vim.api.nvim_get_autocmds({ group = group, buffer = buf1 })
  assert(#au1_again == #au1, "Re-running setup for a buffer must not duplicate its autocmds")

  pcall(vim.api.nvim_del_augroup_by_id, group)
  state.auto_refresh_augroup = nil
  vim.api.nvim_buf_delete(buf1, { force = true })
  vim.api.nvim_buf_delete(buf2, { force = true })
  require("unified").setup({})
  return true
end

-- Regression (#26): a debounce armed by a buffer edit must not repaint the diff
-- after `:Unified reset`. vim.defer_fn's timer outlives the deleted augroup, so
-- the debounced refresh has to bail when the view is no longer active.
function M.test_reset_cancels_pending_auto_refresh()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- Keep the tree out of the way; we only care about the inline diff lifecycle.
  require("unified").setup({ file_tree = { enabled = false } })

  local test_path = utils.create_and_commit_file(repo, "test.txt", { "line 1", "line 2", "line 3" }, "Initial commit")

  vim.cmd("edit " .. test_path)
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "modified line 1" })

  require("unified.command").run("HEAD")

  local diff = require("unified.diff")
  assert(
    vim.wait(1000, function()
      return diff.is_diff_displayed(buffer)
    end),
    "diff should render before we reset"
  )

  -- Arm the real debounce the way a keystroke would, then immediately reset.
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  require("unified.command").reset()

  assert(not diff.is_diff_displayed(buffer), "reset should clear the diff immediately")

  -- Let the pending debounce timer (300ms) fire; the diff must stay gone.
  vim.wait(500, function()
    return false
  end)

  assert(not diff.is_diff_displayed(buffer), "a pending auto-refresh must not resurrect the diff after reset (#26)")

  vim.cmd("bdelete!")
  require("unified").setup({})
  utils.cleanup_git_repo(repo)
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

-- Regression: the default backend must resolve the ref against the *buffer's*
-- git root, the way the inline diff does -- not Neovim's cwd. Launching nvim
-- from a non-repo directory (or a different repo) used to make `:Unified HEAD`
-- fail to resolve HEAD even though the buffer sat in a perfectly good repo.
function M.test_default_backend_resolves_ref_against_buffer_repo()
  local original_cwd = vim.fn.getcwd()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified").setup({ file_tree = { enabled = false } })

  local test_path = utils.create_and_commit_file(repo, "test.txt", { "line 1", "line 2", "line 3" }, "Initial commit")

  -- Open and modify the buffer while cwd is still the repo, so its name resolves
  -- to an absolute path before we move cwd elsewhere.
  vim.cmd("edit " .. test_path)
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "modified line 1" })

  -- Move nvim's cwd out of the repo, into a fresh directory that is not a git
  -- repo. Resolving HEAD here would fail; resolving it in the buffer's repo works.
  local outside = vim.fn.tempname()
  vim.fn.mkdir(outside, "p")
  vim.cmd("lcd " .. outside)

  require("unified.command").run("HEAD")

  local diff = require("unified.diff")
  local shown = vim.wait(1000, function()
    return diff.is_diff_displayed(buffer)
  end)

  -- Restore cwd before asserting so a failure can't strand us in a dir we delete.
  vim.cmd("lcd " .. original_cwd)
  assert(shown, "default backend must resolve the ref against the buffer's repo, not nvim's cwd")

  require("unified.command").reset()
  vim.cmd("bdelete!")
  require("unified").setup({})
  vim.fn.delete(outside, "rf")
  utils.cleanup_git_repo(repo)
  return true
end

-- Regression: viewing a file that has been deleted from disk must not clobber a
-- buffer that still holds unsaved content. The "whole file deleted" view overwrites
-- the buffer with the committed blob and resets 'modified', so firing it on a live
-- buffer silently destroyed the user's edits. It must run only for an empty buffer
-- (a throwaway view); otherwise the diff follows the buffer's current content.
function M.test_deleted_file_view_does_not_clobber_modified_buffer()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified").setup({ file_tree = { enabled = false } })

  local path = utils.create_and_commit_file(repo, "foo.txt", { "line 1", "line 2", "line 3" }, "Initial commit")

  vim.cmd("edit " .. path)
  local buffer = vim.api.nvim_get_current_buf()

  -- Unsaved edit, then the file vanishes from disk (external rm, branch switch, ...).
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "my unsaved edit" })
  vim.fn.delete(path)
  assert(vim.fn.filereadable(path) == 0, "precondition: file must be gone from disk")

  require("unified.git").show_git_diff_against_commit("HEAD", buffer)

  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  assert(lines[1] == "my unsaved edit", "deleted-file view must not overwrite the buffer's unsaved content")
  assert(vim.bo[buffer].modified == true, "deleted-file view must not reset 'modified' on a live buffer")

  require("unified.command").reset()
  vim.cmd("bdelete!")
  require("unified").setup({})
  utils.cleanup_git_repo(repo)
  return true
end

-- Regression: the whole-file "deleted" view (every committed line highlighted red) must
-- survive a re-render. Opening a deleted path from the tree loads an empty buffer, so the
-- first render takes the deleted-file branch and fills the buffer with the committed blob.
-- Auto-refresh then calls show_git_diff_against_commit again -- but the buffer is no longer
-- empty. The emptiness guard used to skip the deleted view on that second pass, collapsing
-- the all-red view. The buffer must keep every line marked as deleted across the refresh.
function M.test_deleted_file_view_persists_across_refresh()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified").setup({ file_tree = { enabled = false } })

  local path = utils.create_and_commit_file(repo, "gone.txt", { "alpha", "beta", "gamma", "delta" }, "add gone.txt")
  vim.fn.delete(path)
  assert(vim.fn.filereadable(path) == 0, "precondition: file must be gone from disk")

  -- Mirror how the tree opens a deleted node: load the missing path into an empty buffer.
  local buffer = vim.fn.bufadd(path)
  vim.fn.bufload(buffer)

  local function count_delete_marks()
    local ns = require("unified.config").ns_id
    local marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, { details = true })
    local n = 0
    for _, mark in ipairs(marks) do
      if mark[4] and mark[4].line_hl_group == "UnifiedDiffDelete" then
        n = n + 1
      end
    end
    return n
  end

  local git = require("unified.git")

  assert(git.show_git_diff_against_commit("HEAD", buffer), "first render should succeed")
  local first = count_delete_marks()
  assert(first > 0, "deleted-file view should highlight every committed line as deleted")

  -- Auto-refresh re-runs the same call; the all-red view must not collapse.
  assert(git.show_git_diff_against_commit("HEAD", buffer), "re-render should succeed")
  local second = count_delete_marks()
  assert(
    second == first,
    string.format("deleted-file view must persist across refresh (had %d marks, now %d)", first, second)
  )

  require("unified.command").reset()
  vim.cmd("bdelete!")
  require("unified").setup({})
  utils.cleanup_git_repo(repo)
  return true
end

-- Regression: an unmodified, committed *empty* file (0 bytes) must show no diff.
-- Neovim represents an empty buffer as a single empty line with 'endofline' set, so
-- buffer_text used to yield "\n" and diff it against the empty blob -- a spurious
-- change on common empty files (.gitkeep, empty __init__.py, ...).
function M.test_unmodified_empty_file_shows_no_diff()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  require("unified").setup({ file_tree = { enabled = false } })

  -- writefile({}) commits a true 0-byte file.
  local path = utils.create_and_commit_file(repo, "empty.txt", {}, "add empty file")

  vim.cmd("edit " .. path)
  local buffer = vim.api.nvim_get_current_buf()

  require("unified.git").show_git_diff_against_commit("HEAD", buffer)

  assert(
    not require("unified.diff").is_diff_displayed(buffer),
    "an unmodified empty file must not show a diff against its empty blob"
  )

  require("unified.command").reset()
  vim.cmd("bdelete!")
  require("unified").setup({})
  utils.cleanup_git_repo(repo)
  return true
end

-- Regression: is_diff_displayed is a predicate and must never throw. Auto-refresh
-- queries it from a buffer-local autocmd; if that buffer is ever interrogated once
-- it has stopped being valid, the only sensible answer is "no diff here" -- false --
-- not an "Invalid buffer id" error surfaced as a toast.
function M.test_is_diff_displayed_false_for_invalid_buffer()
  require("unified").setup({})

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_delete(buf, { force = true })
  assert(not vim.api.nvim_buf_is_valid(buf), "buffer should be invalid after delete")

  assert(
    require("unified.diff").is_diff_displayed(buf) == false,
    "is_diff_displayed must return false for an invalid buffer, not throw"
  )

  return true
end

return M
