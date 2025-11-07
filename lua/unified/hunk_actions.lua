local M = {}
local Job = require("unified.utils.job")
local Diff = require("unified.diff")
local State = require("unified.state")

local function get_buf_and_path()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  if ft == "unified_tree" then
    vim.api.nvim_echo(
      { { "Unified: hunk actions are not available in the file tree buffer", "WarningMsg" } },
      false,
      {}
    )
    return nil
  end
  local abs = vim.api.nvim_buf_get_name(buf)
  if abs == "" then
    vim.api.nvim_echo({ { "Unified: buffer has no file path", "ErrorMsg" } }, false, {})
    return nil
  end
  return buf, abs
end

local function dirname(path)
  return vim.fn.fnamemodify(path, ":h")
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

local function find_git_root(start_dir)
  local out, code = Job.await({ "git", "rev-parse", "--show-toplevel" }, { cwd = start_dir })
  if code == 0 and out and out ~= "" then
    return vim.trim(out)
  end
  -- fallback: walk up to 10 dirs
  local current = start_dir
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

local function relpath(abs, root)
  if abs:sub(1, #root) == root then
    local rel = abs:sub(#root + 2)
    return rel
  end
  return nil
end

local function read_patch(root, rel, mode)
  local cmd = { "git", "diff", "-U0", "--", rel }
  if mode == "cached" then
    cmd = { "git", "diff", "-U0", "--cached", "--", rel }
  end
  local out, code, err = Job.await(cmd, { cwd = root })
  if code ~= 0 then
    return nil, err or "git diff failed"
  end
  if out == nil or out == "" then
    return nil, "No diff for file"
  end
  if out:match("^Binary files") or out:find("\nBinary files ") then
    return nil, "Binary patch not supported"
  end
  return out, nil
end

local function parse_patch(patch_text)
  local lines = vim.split(patch_text, "\n", { plain = true })
  local headers = {}
  local hunks = {}
  local i = 1
  -- collect headers until first @@
  while i <= #lines and not lines[i]:match("^@@") do
    table.insert(headers, lines[i])
    i = i + 1
  end
  while i <= #lines do
    if not lines[i]:match("^@@") then
      -- skip unexpected lines
      i = i + 1
    else
      local header = lines[i]
      local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      old_count = (old_count ~= "" and tonumber(old_count)) or 1
      new_count = (new_count ~= "" and tonumber(new_count)) or 1
      local h = {
        header = header,
        old_start = tonumber(old_start),
        old_count = old_count,
        new_start = tonumber(new_start),
        new_count = new_count,
        lines = {},
      }
      i = i + 1
      while i <= #lines and not lines[i]:match("^@@") do
        -- keep exact lines (including empty strings) until next hunk
        table.insert(h.lines, lines[i])
        i = i + 1
      end
      table.insert(hunks, h)
    end
  end
  return { headers = headers, hunks = hunks }
end

local function pick_hunk_for_cursor(hunks, cursor_line)
  local best
  for _, h in ipairs(hunks) do
    if h.new_count and h.new_count > 0 then
      if cursor_line >= h.new_start and cursor_line < h.new_start + h.new_count then
        return h
      end
    else
      if cursor_line == h.new_start or cursor_line == math.max(1, h.new_start - 1) then
        return h
      end
    end
    -- track nearest as fallback
    local target = (h.new_count and h.new_count > 0) and h.new_start or math.max(1, h.new_start - 1)
    if not best or math.abs(cursor_line - target) < math.abs(cursor_line - best._dist_anchor) then
      best = h
      best._dist_anchor = target
    end
  end
  return best
end

local function build_single_hunk_patch(rel, parsed, hunk)
  local buff = {}
  -- keep essential headers: if missing ---/+++ add them
  local has_oldnew = false
  for _, l in ipairs(parsed.headers) do
    if l:match("^--- ") or l:match("^%+%+%+ ") then
      has_oldnew = true
    end
    table.insert(buff, l)
  end
  if not has_oldnew then
    table.insert(buff, "--- a/" .. rel)
    table.insert(buff, "+++ b/" .. rel)
  end
  table.insert(buff, hunk.header)
  for _, l in ipairs(hunk.lines) do
    table.insert(buff, l)
  end
  if buff[#buff] ~= "" then
    table.insert(buff, "")
  end
  return table.concat(buff, "\n")
end

local function apply_patch(root, patch, args)
  local tmp = write_tmp(patch)
  local cmd = { "git", "apply", "--unidiff-zero", "--whitespace=nowarn" }
  for _, a in ipairs(args or {}) do
    table.insert(cmd, a)
  end
  table.insert(cmd, tmp)
  local out, code, err = Job.await(cmd, { cwd = root })
  vim.fn.delete(tmp)
  return code == 0, (err ~= "" and err or out)
end

local function do_action(which)
  local buf, abs = get_buf_and_path()
  if not buf then
    return
  end
  local root = find_git_root(dirname(abs))
  if not root then
    vim.api.nvim_echo({ { "Unified: not a git repository", "ErrorMsg" } }, false, {})
    return
  end
  local rel = relpath(abs, root)
  if not rel or rel == "" then
    vim.api.nvim_echo({ { "Unified: could not compute file path relative to repo", "ErrorMsg" } }, false, {})
    return
  end
  local mode = (which == "unstage") and "cached" or "working"
  local patch_text, err = read_patch(root, rel, mode)
  if not patch_text then
    vim.api.nvim_echo({ { "Unified: " .. err, "WarningMsg" } }, false, {})
    return
  end
  local parsed = parse_patch(patch_text)
  if not parsed.hunks or #parsed.hunks == 0 then
    vim.api.nvim_echo({ { "Unified: no hunks found for file", "WarningMsg" } }, false, {})
    return
  end
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local h = pick_hunk_for_cursor(parsed.hunks, cursor_line)
  if not h then
    vim.api.nvim_echo({ { "Unified: could not determine current hunk", "WarningMsg" } }, false, {})
    return
  end
  local single = build_single_hunk_patch(rel, parsed, h)
  local args = {}
  if which == "stage" then
    args = { "--cached" }
  elseif which == "unstage" then
    args = { "--cached", "-R" }
  elseif which == "revert" then
    args = { "-R" }
  else
    vim.api.nvim_echo({ { "Unified: unknown action " .. tostring(which), "ErrorMsg" } }, false, {})
    return
  end
  local ok, msg = apply_patch(root, single, args)
  if not ok then
    vim.api.nvim_echo({ { "Unified: git apply failed: " .. (msg or ""), "ErrorMsg" } }, false, {})
    return
  end
  -- Always reload the buffer to pick up external changes made by git apply
  pcall(vim.cmd, "checktime")
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_call, buf, function()
      vim.cmd("edit!")
    end)
  end
  -- refresh inline diff and tree
  Diff.show_current()
  local ok_base, base = pcall(State.get_commit_base)
  if ok_base and base then
    local ftree = require("unified.file_tree")
    ftree.show(base)
  end
end

function M.stage_hunk()
  do_action("stage")
end
function M.unstage_hunk()
  do_action("unstage")
end
function M.revert_hunk()
  do_action("revert")
end

return M
