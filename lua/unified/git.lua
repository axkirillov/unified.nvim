local M = {}
local config = require("unified.config")
local cache_util = require("unified.utils.cache")

-- Check if file is in a git repository
function M.is_git_repo(file_path)
  -- Get directory from file path
  local dir = file_path
  if vim.fn.isdirectory(file_path) ~= 1 then
    dir = vim.fn.fnamemodify(file_path, ":h")
  end

  -- Use git rev-parse to check if we're in a git repo
  local cmd = string.format("cd %s && git rev-parse --is-inside-work-tree 2>/dev/null", vim.fn.shellescape(dir))
  local result = vim.fn.system(cmd)
  local is_git_repo = vim.trim(result) == "true"

  if vim.g.unified_debug then
    print("Git repo check for: " .. dir)
    print("Git result: '" .. vim.trim(result) .. "'")
    print("Is git repo: " .. tostring(is_git_repo))
  end

  -- Double check by looking for .git directory
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

M.get_git_file_content = cache_util.memoize(function(file_path, commit)
  commit = commit or "HEAD"

  local relative_path = vim.fn.system(
    string.format(
      "cd %s && git ls-files --full-name %s | tr -d '\n'",
      vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h")),
      vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":t"))
    )
  )

  if relative_path == "" then
    return nil
  end

  local cmd = string.format(
    "cd %s && git show %s:%s 2>/dev/null",
    vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h")),
    vim.fn.shellescape(commit),
    vim.fn.shellescape(relative_path)
  )

  local content = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return content
end)

-- Show diff of the current buffer compared to a specific git commit with improved highlighting
function M.show_git_diff_against_commit(commit)
  local diff_module = require("unified.diff")
  local buffer = vim.api.nvim_get_current_buf()
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

  -- Get content from git at specified commit
  local git_content = M.get_git_file_content(file_path, commit)

  -- If file isn't in git at that commit, treat it as empty for diffing new files
  if not git_content then
    git_content = "" -- Treat as empty content
    -- Do not return false here, proceed to diff against empty content
  end

  -- Check if there are any changes at all
  if current_content == git_content then
    vim.api.nvim_echo(
      { { "No changes detected between buffer and git version at " .. commit, "WarningMsg" } },
      false,
      {}
    )
    -- Clear existing diff marks if no changes
    local ns_id = config.ns_id
    vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
    vim.fn.sign_unplace("unified_diff", { buffer = buffer })
    return false
  end

  -- Create temporary files for diffing
  local temp_current = vim.fn.tempname()
  local temp_git = vim.fn.tempname()

  -- Write current buffer content to temp file
  vim.fn.writefile(vim.split(current_content, "\n"), temp_current)
  vim.fn.writefile(vim.split(git_content, "\n"), temp_git)

  -- We'll use git diff instead of plain diff for better accuracy
  local dir = vim.fn.fnamemodify(file_path, ":h")

  -- Use git diff with unified format for better visualization
  local diff_cmd = string.format(
    "cd %s && git diff --no-index --unified=3 --text --no-color --word-diff=none %s %s",
    vim.fn.shellescape(dir),
    vim.fn.shellescape(temp_git),
    vim.fn.shellescape(temp_current)
  )

  local diff_output = vim.fn.system(diff_cmd)

  -- Clean up temp files
  vim.fn.delete(temp_current)
  vim.fn.delete(temp_git)

  if diff_output ~= "" then
    -- Remove the git diff header lines that might confuse our parser
    diff_output = diff_output:gsub("diff %-%-git a/%S+ b/%S+\n", "") -- Match --no-index header
    diff_output = diff_output:gsub("index %S+%.%.%S+ %S+\n", "")
    diff_output = diff_output:gsub("%-%-%" .. "- %S+\n", "") -- Split the string to avoid escaping issues
    diff_output = diff_output:gsub("%+%+%+" .. " %S+\n", "") -- Split the string to avoid escaping issues

    local hunks = diff_module.parse_diff(diff_output)
    local result = diff_module.display_inline_diff(buffer, hunks) -- Use diff_module
    return result
  else
    vim.api.nvim_echo({ { "No differences found by diff command", "WarningMsg" } }, false, {})
    -- Clear existing diff marks if no changes found by diff command
    local ns_id = config.ns_id
    vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
    vim.fn.sign_unplace("unified_diff", { buffer = buffer })
  end

  return false
end

-- Show diff of the current buffer compared to git HEAD
function M.show_git_diff()
  return M.show_git_diff_against_commit("HEAD")
end

return M
