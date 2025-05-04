local M = {}
local config = require("unified.config")
local cache_util = require("unified.utils.cache")
local job = require("unified.utils.job")

-- Check if file is in a git repository
function M.is_git_repo(file_path)
  -- Get directory from file path
  local dir = file_path
  if vim.fn.isdirectory(file_path) ~= 1 then
    dir = vim.fn.fnamemodify(file_path, ":h")
  end

  -- Use git rev-parse to check if we're in a git repo
  local out, code = job.await({ "git", "rev-parse", "--is-inside-work-tree" }, { cwd = dir, ignore_stderr = true })
  local is_git_repo = code == 0 and vim.trim(out) == "true"

  if vim.g.unified_debug then
    print("Git repo check for: " .. dir)
    print("Git result: '" .. vim.trim(out or "") .. "', code: " .. tostring(code))
    print("Is git repo: " .. tostring(is_git_repo))
  end

  if not is_git_repo then
    -- Try to find .git directory by traversing up
    local check_dir = dir
    local max_depth = 10 -- Avoid infinite loops
    for _ = 1, max_depth do
      if vim.fn.isdirectory(check_dir .. "/.git") == 1 then
        is_git_repo = true
        if vim.g.unified_debug then
          print("Found .git directory in: " .. check_dir)
        end
        break
      end

      -- Go up one directory
      local parent = vim.fn.fnamemodify(check_dir, ":h")
      if parent == check_dir then
        -- We've reached the root, stop
        break
      end
      check_dir = parent
    end
  end

  return is_git_repo
end

---@param commit_ref string The commit reference (e.g., 'HEAD', branch name, tag, hash).
---@param cwd string The working directory for the git command.
---@param cb function|nil An optional callback function `cb(hash)` called with the resolved hash (string) or nil on failure.
function M.resolve_commit_hash(commit_ref, cwd, cb)
  local cmd = { "git", "rev-parse", "--verify", commit_ref }
  job.run(cmd, { cwd = cwd, ignore_stderr = true }, function(out, code)
    local hash = nil
    if code == 0 then
      hash = vim.trim(out or "")
      if hash == "" then
        hash = nil
      end
    end

    if vim.g.unified_debug and not hash then
      print("Failed to resolve commit reference: " .. commit_ref .. " in " .. cwd .. " (code: " .. code .. ")")
    end

    if cb then
      vim.schedule(function()
        cb(hash)
      end)
    end
  end)
end

M.get_git_file_content = cache_util.memoize(function(file_path, commit)
  local file_dir = vim.fn.fnamemodify(file_path, ":h")
  local root_out, root_code = job.await({ "git", "rev-parse", "--show-toplevel" }, { cwd = file_dir })

  if root_code ~= 0 then
    vim.api.nvim_err_writeln("Failed to find git root for: " .. file_path)
    return nil
  end
  local git_root = vim.trim(root_out)

  local rel_path_out, rel_path_code = job.await(
    { "git", "ls-files", "--full-name", "--", file_path },
    { cwd = git_root }
  )

  if rel_path_code ~= 0 or vim.trim(rel_path_out) == "" then
    return ""
  end
  local relative_path = vim.trim(rel_path_out)

  local content_out, content_code = job.await(
    { "git", "show", commit .. ":" .. relative_path },
    { cwd = git_root, ignore_stderr = true }
  )

  if content_code ~= 0 then
    vim.api.nvim_err_writeln("Failed to get content for: " .. relative_path .. " at commit: " .. commit)
    return nil
  end

  return content_out
end)

---@param commit string
---@param buffer_id integer The buffer ID to operate on.
function M.show_git_diff_against_commit(commit, buffer_id)
  local diff_module = require("unified.diff")
  local buffer = buffer_id -- Use the passed buffer ID

  -- Validate buffer ID
  if not vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_echo({ { "Invalid buffer ID passed to show_git_diff_against_commit", "ErrorMsg" } }, false, {})
    return false
  end

  local current_content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  local file_path = vim.api.nvim_buf_get_name(buffer)

  -- Skip if buffer has no name
  if file_path == "" then
    vim.api.nvim_echo({ { "Buffer has no file name", "ErrorMsg" } }, false, {})
    return false
  end

  -- Check if file is in a git repo
  if not M.is_git_repo(file_path) then
    vim.api.nvim_echo({ { "File is not in a git repository", "WarningMsg" } }, false, {})
    return false
  end

  local dir = vim.fn.fnamemodify(file_path, ":h")
  M.resolve_commit_hash(commit, dir, function(commit_hash)
    vim.schedule(function()
      if not commit_hash then
        vim.api.nvim_echo({ { "Invalid commit reference: " .. commit .. " in " .. dir, "ErrorMsg" } }, false, {})
        return
      end

      local git_content = M.get_git_file_content(file_path, commit_hash)

      if git_content == "" then
        -- fall through – let the diff section compare "" vs current content
      elseif not git_content then
        vim.api.nvim_echo({
          { "Failed to retrieve content from commit " .. commit_hash, "WarningMsg" },
        }, false, {})
        return
      end

      if current_content == git_content then
        vim.api.nvim_echo(
          { { "No changes detected between buffer and git version at " .. commit, "WarningMsg" } },
          false,
          {}
        )
        local ns_id = config.ns_id
        vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
        vim.fn.sign_unplace("unified_diff", { buffer = buffer })
        return
      end

      local temp_current = vim.fn.tempname()
      local temp_git = vim.fn.tempname()

      vim.fn.writefile(vim.split(current_content, "\n"), temp_current)
      vim.fn.writefile(vim.split(git_content, "\n"), temp_git)

      job.run({
        "git",
        "diff",
        "--no-index",
        "--unified=3",
        "--text",
        "--no-color",
        "--word-diff=none",
        temp_git,
        temp_current,
      }, { cwd = dir }, function(diff_output, code, err)
        vim.fn.delete(temp_current)
        vim.fn.delete(temp_git)

        vim.schedule(function()
          if (code == 0 or code == 1) and diff_output and diff_output ~= "" then
            diff_output = diff_output:gsub("diff %-%-git a/%S+ b/%S+\n", "")
            diff_output = diff_output:gsub("index %S+%.%.%S+ %S+\n", "")
            diff_output = diff_output:gsub("%-%-%" .. "- %S+\n", "")
            diff_output = diff_output:gsub("%+%+%+" .. " %S+\n", "")

            local hunks = diff_module.parse_diff(diff_output)
            diff_module.display_inline_diff(buffer, hunks)
          elseif code ~= 0 and code ~= 1 then
            vim.api.nvim_echo({ { "Error running git diff: " .. (err or "Unknown error"), "ErrorMsg" } }, false, {})
            local ns_id = config.ns_id
            vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
            vim.fn.sign_unplace("unified_diff", { buffer = buffer })
          else
            vim.api.nvim_echo({ { "No differences found by diff command", "WarningMsg" } }, false, {})
            local ns_id = config.ns_id
            vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
            vim.fn.sign_unplace("unified_diff", { buffer = buffer })
          end
        end)
      end)
    end)
  end)
  return true
end

return M
