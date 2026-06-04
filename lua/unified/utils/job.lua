-- utils/job.lua --------------------------------------------------------------
-- Thin, coroutine-friendly wrapper around vim.system()  (Neovim ≥ 0.10)
-- Usage:
--   local job = require('unified.utils.job')
--   job.run({ 'git', 'status', '--porcelain' }, { cwd = dir }, function(out, code) … end)
--   job.await({ 'git', 'rev-parse', 'HEAD' })                    -- ⇢ stdout , code

local Job = {}

-- vim.system() validates its opts eagerly and *throws* before the process ever
-- starts -- most notably when opts.cwd does not exist, which happens when a git
-- command is derived from a non-file buffer (a term:// buffer's name is not a
-- real path). A fire-and-forget async wrapper must never let that surface as an
-- uncaught editor error, so a failed spawn is reported as a failed command: a
-- non-zero exit through the normal callback/return. -1 is distinct from git's own
-- exit codes (0/1/128) so callers that special-case those -- e.g. 128 meaning
-- "path not in tree" -- never mistake a spawn failure for one.
local SPAWN_FAILED = -1

-- internal: start process and collect plain-text I/O -------------------------
local function _spawn(cmd, opts, on_exit)
  opts = vim.tbl_extend("force", { text = true }, opts or {})
  local ok, handle = pcall(vim.system, cmd, opts, function(proc)
    vim.schedule(function()
      on_exit(proc.stdout or "", proc.code, proc.stderr)
    end)
  end)
  if not ok then
    -- Schedule like the success path so callers (incl. the coroutine in await)
    -- are always resumed asynchronously, never re-entrantly mid-spawn.
    vim.schedule(function()
      on_exit("", SPAWN_FAILED, tostring(handle))
    end)
    return nil
  end
  return handle
end

-- internal: build a blocking shell command string, honoring opts.cwd/opts.env.
-- Only used on the legacy (pre-0.10) path that lacks vim.system().
local function build_shell_command(cmd, opts)
  local exec_cmd = type(cmd) == "table" and table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ") or cmd
  if opts then
    if opts.env then
      local env_parts = {}
      for k, v in pairs(opts.env) do
        table.insert(env_parts, ("%s=%s"):format(k, vim.fn.shellescape(v)))
      end
      exec_cmd = ("env %s %s"):format(table.concat(env_parts, " "), exec_cmd)
    end
    if opts.cwd then
      exec_cmd = ("cd %s && %s"):format(vim.fn.shellescape(opts.cwd), exec_cmd)
    end
  end
  return exec_cmd
end

---@param cmd  (string|string[] ) command
---@param opts table|nil           { cwd = <dir>, env = {...}, ... }
---@param cb   fun(stdout, code, stderr)|nil
function Job.run(cmd, opts, cb)
  if vim.system then -- 0.10+
    return _spawn(cmd, opts, cb or function() end)
  else
    local final_cmd = build_shell_command(cmd, opts)
    local out = vim.fn.system(final_cmd)
    local code = vim.v.shell_error
    if cb then
      cb(out, code, "")
    end
    return { stdout = out, code = code }
  end
end

--- Await helper (sugar for synchronous code paths that expect a return) ------
--- Must be called from within a coroutine for async behavior.
--- Falls back to a blocking vim.system():wait() if called outside a coroutine,
--- which still honors opts (cwd/env).
---@param cmd  (string|string[] ) command
---@param opts table|nil           { cwd = <dir>, env = {...}, ... }
---@return string|nil stdout       stdout if successful, nil otherwise
---@return number|nil code         exit code if successful, nil otherwise
---@return string|nil stderr       stderr if available, nil otherwise
function Job.await(cmd, opts)
  if not vim.system then -- pre-0.10, nothing to await
    local out = vim.fn.system(build_shell_command(cmd, opts))
    return out, vim.v.shell_error, ""
  end

  local caller_co = coroutine.running()
  -- If we're not inside a coroutine, run synchronously (blocking) but still
  -- honor opts.cwd/opts.env via vim.system():wait().
  if not caller_co then
    if type(cmd) == "table" then
      -- pcall: vim.system() throws on a bad cwd, and this blocking path is what
      -- find_git_root/git_sync use outside a coroutine -- the frames in the
      -- ENOENT crash. Convert the throw into a failed command instead.
      local ok, res = pcall(function()
        return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
      end)
      if not ok then
        return "", SPAWN_FAILED, tostring(res)
      end
      return res.stdout or "", res.code, res.stderr or ""
    end
    local out = vim.fn.system(build_shell_command(cmd, opts))
    return out, vim.v.shell_error, ""
  end

  local results = {}
  _spawn(cmd, opts, function(o, c, e)
    -- Store results and schedule the resumption of the calling coroutine
    results.stdout = o
    results.code = c
    results.stderr = e
    -- It's crucial to resume via vim.schedule to ensure it happens on the main thread
    coroutine.resume(caller_co, results)
  end)

  -- Yield the calling coroutine, waiting for the callback to resume it
  local resume_results = coroutine.yield()

  -- Return the results passed via coroutine.resume
  return resume_results.stdout, resume_results.code, resume_results.stderr
end

return Job
