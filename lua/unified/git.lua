local Job = require("unified.utils.job")
local Cache = require("unified.utils.cache")
local Config = require("unified.config")
local Diff = require("unified.diff")
local Hunk = require("unified.hunk_store")

local M = {}

local function git_async(args, cwd, cb)
  Job.run(args, { cwd = cwd, ignore_stderr = true }, cb)
end

local function git_sync(args, cwd)
  return Job.await(args, { cwd = cwd, ignore_stderr = true })
end

local function find_git_root(path)
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  local stdout, code = git_sync({ "git", "rev-parse", "--show-toplevel" }, dir)
  if code == 0 then
    return vim.trim(stdout)
  end
  local current = dir
  for _ = 1, 10 do
    if vim.fn.isdirectory(current .. "/.git") == 1 then
      return current
    end
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      break
    end
    current = parent
  end
  return nil
end

local function write_tmp(content)
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "wb")
  if f then
    f:write(content)
    f:close()
  end
  return tmp
end

local function clear_diff(buf)
  local ns = Config.ns_id
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buf })
  Hunk.clear(buf)
end

function M.is_git_repo(path)
  return find_git_root(path) ~= nil
end

function M.resolve_commit_hash(ref, cwd, cb)
  git_async({ "git", "rev-parse", "--verify", ref }, cwd, function(out, code)
    vim.schedule(function()
      cb(code == 0 and vim.trim(out) or nil)
    end)
  end)
end

M.get_git_file_content = Cache.memoize(function(abs_path, commit)
  local root = find_git_root(abs_path)
  if not root then
    return nil
  end
  local rel = abs_path:sub(#root + 2)
  if rel == "" then
    return nil
  end
  local out, code = git_sync({ "git", "show", commit .. ":" .. rel }, root)
  if code == 128 then
    return false
  end
  if code ~= 0 then
    return nil
  end
  return out
end)

local function ui_deleted(buf, blob)
  Diff.display_deleted_file(buf, blob)
end

local function ui_inline(buf, diff_output)
  local hunks = Diff.parse_diff(diff_output)
  Diff.display_inline_diff(buf, hunks)
end

local function ui_no_changes(buf)
  clear_diff(buf)
  vim.api.nvim_echo({ { "No changes", "Comment" } }, false, {})
end

local function ui_binary(buf)
  clear_diff(buf)
  vim.api.nvim_buf_set_extmark(buf, Config.ns_id, 0, 0, {
    line_hl_group = "DiffChange",
    end_row = -1,
  })
  vim.api.nvim_echo({ { "Binary files differ", "WarningMsg" } }, false, {})
end

--- @return boolean success
function M.show_git_diff_against_commit(commit, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local abs_path = vim.api.nvim_buf_get_name(buf)
  if abs_path == "" then
    return false
  end
  if not M.is_git_repo(abs_path) then
    return false
  end

  local root = find_git_root(abs_path)
  if not root then
    return false
  end

  -- 1) resolve ref (async → simple wait loop)
  local hash
  local done = false
  M.resolve_commit_hash(commit, root, function(h)
    hash, done = h, true
  end)
  while not done do
    vim.wait(10)
  end
  if not hash then
    return false
  end

  -- 2) gather contents
  local git_blob = M.get_git_file_content(abs_path, hash)
  local cur_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cur_text = table.concat(cur_lines, "\n")
  local file_now = vim.fn.filereadable(abs_path) == 1

  -- 3) decide scenario
  if git_blob == false then -- new file
    if not file_now then
      ui_no_changes(buf)
      return true
    end
    local tmp_cur = write_tmp(cur_text)
    local diff = select(1, git_sync({ "git", "diff", "--no-index", "/dev/null", tmp_cur }, root))
    vim.fn.delete(tmp_cur)
    ui_inline(buf, diff)
    return true
  end

  if git_blob == nil then
    return false
  end -- fetch error

  if not file_now then -- deleted now
    ui_deleted(buf, git_blob)
    return true
  end

  if cur_text == git_blob then -- identical
    ui_no_changes(buf)
    return true
  end

  -- regular diff
  local tmp_git = write_tmp(git_blob)
  local tmp_cur = write_tmp(cur_text)
  local stdout, code = git_sync({ "git", "diff", "--no-index", "--text", tmp_git, tmp_cur }, root)
  vim.fn.delete(tmp_git)
  vim.fn.delete(tmp_cur)

  if stdout:match("^Binary files") then
    ui_binary(buf)
    return true
  end
  if code ~= 0 and code ~= 1 then
    return false
  end -- diff failed

  -- strip noisy headers for clean parsing
  stdout = stdout
    :gsub("diff %-%-git [^\\n]+\\n", "")
    :gsub("index [^\\n]+\\n", "")
    :gsub("%-%-%- [^\\n]+\\n", "")
    :gsub("%+%+%+ [^\\n]+\\n", "")

  ui_inline(buf, stdout)
  return true
end

return M
