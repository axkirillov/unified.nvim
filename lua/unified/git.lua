local M = {}
local config = require("unified.config")
local cache_util = require("unified.utils.cache")
local job = require("unified.utils.job")

local function file_exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

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

  local relative_path

  if file_path:sub(1, #git_root) == git_root then
    relative_path = file_path:sub(#git_root + 2)
  end

  if not relative_path or relative_path == "" then
    local rel_path_out, rel_path_code = job.await(
      { "git", "ls-files", "--full-name", "--", file_path },
      { cwd = git_root }
    )
    if rel_path_code == 0 and vim.trim(rel_path_out) ~= "" then
      relative_path = vim.trim(rel_path_out)
    else
      return ""
    end
  end

  local content_out, content_code = job.await(
    { "git", "show", commit .. ":" .. relative_path },
    { cwd = git_root, ignore_stderr = true }
  )

  if content_code ~= 0 then
    if content_code == 128 then
      return false
    end
    vim.api.nvim_err_writeln("Git error (" .. content_code .. ") retrieving " .. relative_path .. " at " .. commit)
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

      local function run_and_process_diff(current_buffer_id, diff_cwd, diff_command_args, temp_files_to_delete)
        job.run(diff_command_args, { cwd = diff_cwd }, function(diff_output, job_code, job_err)
          if temp_files_to_delete then
            for _, f_path in ipairs(temp_files_to_delete) do
              vim.fn.delete(f_path)
            end
          end

          vim.schedule(function()
            if diff_output and diff_output:match("^Binary files") then
              vim.api.nvim_echo({ { "Binary files differ", "WarningMsg" } }, false, {})
              local ns_id = config.ns_id
              vim.api.nvim_buf_clear_namespace(current_buffer_id, ns_id, 0, -1)
              vim.fn.sign_unplace("unified_diff", { buffer = current_buffer_id })
              vim.api.nvim_buf_set_extmark(
                current_buffer_id,
                ns_id,
                0,
                0,
                { line_hl_group = "DiffChange", end_row = -1 }
              )
            elseif (job_code == 0 or job_code == 1) and diff_output and diff_output ~= "" then
              diff_output = diff_output:gsub("diff %-%-git a/%S+ b/%S+\n", "")
              diff_output = diff_output:gsub("index %S+%.%.%S+ %S+\n", "")
              diff_output = diff_output:gsub("%-%-%" .. "- %S+\n", "")
              diff_output = diff_output:gsub("%+%+%+" .. " %S+\n", "")

              local hunks = diff_module.parse_diff(diff_output)
              diff_module.display_inline_diff(current_buffer_id, hunks)
            else
              local ns_id = config.ns_id
              vim.api.nvim_buf_clear_namespace(current_buffer_id, ns_id, 0, -1)
              vim.fn.sign_unplace("unified_diff", { buffer = current_buffer_id })
              if job_code > 1 then
                vim.api.nvim_echo(
                  { { "Error running git diff: " .. (job_err or "Unknown error"), "ErrorMsg" } },
                  false,
                  {}
                )
              end
            end
          end)
        end)
      end

      local git_content_result = M.get_git_file_content(file_path, commit_hash)
      local diff_args
      local temp_files_to_delete = {}

      if git_content_result == false then -- File was new (marker from get_git_file_content)
        -- Deleted in working tree but get_git_file_content said it's new? This case should not happen.
        -- If file_exists(file_path) is false, it means it's deleted.
        -- But get_git_file_content returning `false` means it was not in the commit.
        -- So this is a new file that is currently empty or has content.
        if not file_exists(file_path) then -- New file, that is also currently deleted (e.g. staged for add, then deleted)
          -- This is an edge case: file was new relative to commit, and is *also* deleted now.
          -- Diffing /dev/null against a non-existent file_path might error.
          -- Treat as "no changes" or "empty file" for display?
          -- For now, let's assume if it's new and doesn't exist, it's like an empty new file.
          -- The original logic for "Deleted in working tree but exists in commit" handles full file display.
          -- This is "New in working tree (relative to commit) but now deleted".
          -- Displaying nothing or "no changes" seems appropriate.
          vim.api.nvim_echo(
            { { "File is new relative to commit and also currently deleted.", "WarningMsg" } },
            false,
            {}
          )
          local ns_id = config.ns_id
          vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
          vim.fn.sign_unplace("unified_diff", { buffer = buffer })
          return
        end

        diff_args = {
          "git",
          "diff",
          "--no-index",
          "--unified=3",
          "--text",
          "--no-color",
          "--word-diff=none",
          "/dev/null",
          file_path,
        }
        -- No temp files to create or delete for this branch
        run_and_process_diff(buffer, dir, diff_args, nil)
      elseif git_content_result == nil then -- Error from get_git_file_content (not code 128)
        vim.api.nvim_echo({
          {
            "Failed to retrieve content for "
              .. vim.fn.fnamemodify(file_path, ":t")
              .. " from commit "
              .. commit_hash:sub(1, 7),
            "WarningMsg",
          },
        }, false, {})
        return
      else -- git_content_result is a string (actual content from commit, or "" if it was empty)
        -- Handle case: Deleted in working tree but existed in the commit
        if (not file_exists(file_path)) and git_content_result ~= "" then
          -- diff_module is already required at the top of parent function
          diff_module.display_deleted_file(buffer, git_content_result)
          return -- display_deleted_file handles it. Original code returned true, but we are in scheduled func.
        end

        if current_content == git_content_result then
          vim.api.nvim_echo(
            { { "No changes detected between buffer and git version at " .. commit_hash:sub(1, 7), "WarningMsg" } },
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

        local file_git = io.open(temp_git, "wb")
        if file_git then
          file_git:write(git_content_result)
          file_git:close()
        else
          vim.api.nvim_err_writeln("Could not open temp file for git content.")
          return
        end

        vim.api.nvim_buf_call(buffer, function()
          vim.cmd("silent noautocmd write! " .. vim.fn.fnameescape(temp_current))
        end)

        table.insert(temp_files_to_delete, temp_current)
        table.insert(temp_files_to_delete, temp_git)

        diff_args = {
          "git",
          "diff",
          "--no-index",
          "--unified=3",
          temp_git,
          temp_current,
        }
        run_and_process_diff(buffer, dir, diff_args, temp_files_to_delete)
      end
    end)
  end)
  return true
end

return M
