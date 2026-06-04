-- Tests for `:Unified` command behavior when invoked from a buffer that is not
-- backed by a real file (a terminal, help, quickfix, ... buffer).
--
-- Launching from such a buffer is supported: the ref resolves against Neovim's
-- cwd and the repo-wide file tree opens, but there is no inline diff (a non-file
-- buffer has no file to follow) and the non-file window is never claimed as the
-- content window. Regression: this used to crash -- the default backend derived
-- git's cwd from the buffer name, but a term:// name is not a filesystem path, so
-- vim.system() threw ENOENT (cwd). The Job spawn boundary now also never throws on
-- a bad cwd; it reports a failed command instead.
local M = {}

local utils = require("test.test_utils")

local function clean_slate()
  pcall(require("unified.command").reset)
  local state = require("unified.state")
  state.file_tree_win = nil
  state.file_tree_buf = nil
  require("unified.config").setup({})
end

M.setup = clean_slate
M.teardown = clean_slate

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

local function buffer_has_diff(buffer)
  return #vim.api.nvim_buf_get_extmarks(buffer, require("unified.config").ns_id, 0, -1, {}) > 0
end

-- Launching from a non-file buffer resolves the ref against Neovim's cwd (not the
-- buffer's bogus name), activates the repo-wide view, shows no inline diff, and
-- does not claim the non-file window as the content window.
function M.test_unified_from_non_file_buffer_resolves_against_cwd_and_activates()
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end

  -- create_git_repo lcd's into the repo, so getcwd() is the repo root.
  require("unified.config").setup({ file_tree = { enabled = false } })
  utils.create_and_commit_file(repo, "test.txt", { "line 1" }, "Initial commit")
  local expected_cwd = vim.fn.getcwd()

  -- A non-file buffer (terminal-like): buftype ~= "" and a name that is not a path.
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_name(buf, "term://" .. repo.repo_dir .. "//4242:zsh")
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()

  local hash = utils.get_current_commit_hash(repo.repo_dir)
  assert(hash, "expected a HEAD hash to diff against")

  -- Spy on resolution to prove the cwd, not the buffer's bogus dir, is used.
  local git = require("unified.git")
  local orig_resolve = git.resolve_commit_hash
  local resolve_dir
  ---@diagnostic disable-next-line: duplicate-set-field
  git.resolve_commit_hash = function(ref, dir, cb)
    resolve_dir = dir
    return orig_resolve(ref, dir, cb)
  end

  local ok = pcall(function()
    require("unified.command").run(hash)
  end)

  local active = ok and wait_until(function()
    return require("unified.state").is_active()
  end)
  -- Give any (erroneous) inline diff a chance to appear before asserting it didn't.
  vim.wait(100, function() end, 1, false)
  local has_diff = buffer_has_diff(buf)
  local main_win = require("unified.state").main_win

  -- Restore before asserting so a failure can never leak the stub.
  git.resolve_commit_hash = orig_resolve

  assert(ok, ":Unified from a non-file buffer must not throw")
  assert(resolve_dir == expected_cwd, "ref should resolve against nvim's cwd, got " .. tostring(resolve_dir))
  assert(active, "launching from a non-file buffer should activate the repo-wide view")
  assert(not has_diff, "a non-file buffer must not be diffed inline")
  assert(main_win ~= win, "the non-file window must not become the content window")

  pcall(require("unified.command").reset)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  utils.cleanup_git_repo(repo)
  return true
end

-- get_main_window must never hand back a non-file window: opening a file there
-- would clobber a terminal. With only a terminal and the tree open, there is no
-- content window, so it returns nil and the tree-open path makes its own split.
function M.test_get_main_window_skips_non_file_windows()
  local state = require("unified.state")

  -- Force a known layout: exactly a non-file window plus a stand-in tree window.
  pcall(vim.cmd, "tabonly")
  pcall(vim.cmd, "only")

  local nofile = vim.api.nvim_create_buf(true, false)
  vim.bo[nofile].buftype = "nofile"
  vim.api.nvim_set_current_buf(nofile)
  local nofile_win = vim.api.nvim_get_current_win()

  vim.cmd("vsplit")
  state.file_tree_win = vim.api.nvim_get_current_win()
  state.main_win = nil

  local got = state.get_main_window()

  -- Restore before asserting so a failure can't leak window/state.
  state.file_tree_win = nil
  state.main_win = nil
  pcall(vim.api.nvim_buf_delete, nofile, { force = true })
  pcall(vim.cmd, "only")

  assert(got ~= nofile_win, "get_main_window must not return a non-file (terminal) window")
  assert(got == nil, "with only a terminal and the tree open, there is no content window")
  return true
end

-- The crashing frame was resolve_commit_hash -> git_async. A non-existent cwd must
-- now resolve to nil (ref unresolvable), never throw.
function M.test_resolve_commit_hash_survives_bad_cwd()
  local git = require("unified.git")
  local bogus = "term://unified-nvim/no/such/dir/" .. tostring(vim.loop.hrtime())

  local done, result = false, "unset"
  local ok = pcall(function()
    git.resolve_commit_hash("HEAD", bogus, function(hash)
      result = hash
      done = true
    end)
  end)
  assert(ok, "resolve_commit_hash must not throw on a non-existent cwd")
  assert(
    wait_until(function()
      return done
    end),
    "resolve_commit_hash must still invoke its callback"
  )
  assert(result == nil, "a bad cwd should resolve to nil, got " .. tostring(result))
  return true
end

-- The spawn boundary: both the async (Job.run) and the blocking (Job.await, used by
-- find_git_root/git_sync outside a coroutine) paths must convert a vim.system()
-- throw into a failed command rather than let it escape.
function M.test_job_survives_bad_cwd()
  local Job = require("unified.utils.job")
  local bogus = "term://unified-nvim/no/such/dir/" .. tostring(vim.loop.hrtime())

  -- async
  local got
  local ok_run = pcall(function()
    Job.run({ "git", "rev-parse", "HEAD" }, { cwd = bogus }, function(out, code)
      got = { out = out, code = code }
    end)
  end)
  assert(ok_run, "Job.run must not throw on a non-existent cwd")
  assert(
    wait_until(function()
      return got ~= nil
    end),
    "Job.run must still invoke its callback"
  )
  assert(got.code ~= 0, "a bad cwd should report a non-zero exit, got " .. tostring(got.code))

  -- blocking (no surrounding coroutine -> the :wait() path)
  local code
  local ok_await = pcall(function()
    _, code = Job.await({ "git", "rev-parse", "HEAD" }, { cwd = bogus })
  end)
  assert(ok_await, "Job.await must not throw on a non-existent cwd")
  assert(code ~= 0, "Job.await should report a non-zero exit on a bad cwd, got " .. tostring(code))

  return true
end

return M
