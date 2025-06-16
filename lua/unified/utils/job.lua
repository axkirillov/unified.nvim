-- utils/job.lua --------------------------------------------------------------
-- Thin, coroutine-friendly wrapper around vim.system()  (Neovim ≥ 0.10)
-- Usage:
--   local job = require('unified.utils.job')
--   job.run({ 'git', 'status', '--porcelain' }, { cwd = dir }, function(out, code) … end)
--   job.await({ 'git', 'rev-parse', 'HEAD' })                    -- ⇢ stdout , code

local Job = {}

-- internal: start process and collect plain-text I/O -------------------------
local function _spawn(cmd, opts, on_exit)
  opts = vim.tbl_extend("force", { text = true }, opts or {})
  return vim.system(cmd, opts, function(proc)
    vim.schedule(function()
      on_exit(proc.stdout or "", proc.code, proc.stderr)
    end)
  end)
end

---@param cmd  (string|string[] ) command
---@param opts table|nil           { cwd = <dir>, env = {...}, ... }
---@param cb   fun(stdout, code, stderr)|nil
function Job.run(cmd, opts, cb)
  if vim.system then -- 0.10+
    return _spawn(cmd, opts, cb or function() end)
  else
    local exec_cmd = type(cmd) == "table" and table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ") or cmd

    local final_cmd = exec_cmd
    if opts then
      if opts.env then
        local env_parts = {}
        for k, v in pairs(opts.env) do
          table.insert(env_parts, ("%s=%s"):format(k, vim.fn.shellescape(v)))
        end
        final_cmd = ("env %s %s"):format(table.concat(env_parts, " "), final_cmd)
      end
      if opts.cwd then
        final_cmd = ("cd %s && %s"):format(vim.fn.shellescape(opts.cwd), final_cmd)
      end
    end
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
--- Falls back to blocking vim.fn.system if called outside a coroutine.
---@param cmd  (string|string[] ) command
---@param opts table|nil           { cwd = <dir>, env = {...}, ... }
---@return string|nil stdout       stdout if successful, nil otherwise
---@return number|nil code         exit code if successful, nil otherwise
---@return string|nil stderr       stderr if available, nil otherwise
function Job.await(cmd, opts)
  if not vim.system then -- pre-0.10, nothing to await
    local exec_cmd = type(cmd) == "table" and table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ") or cmd
    local out = vim.fn.system(exec_cmd)
    local code = vim.v.shell_error
    return out, code, "" -- Return empty stderr for consistency
  end

  local caller_co = coroutine.running()
  -- If we're not inside a coroutine, run the command synchronously (blocking)
  if not caller_co then
    local exec_cmd = type(cmd) == "table" and table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ") or cmd
    local out = vim.fn.system(exec_cmd)
    local code = vim.v.shell_error
    return out, code, "" -- keep the same return shape
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
