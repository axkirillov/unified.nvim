local M = {}

-- Configuration with default values
M.config = {
  signs = {
    add = "│",
    delete = "│",
    change = "│",
  },
  highlights = {
    add = "DiffAdd",
    delete = "DiffDelete",
    change = "DiffChange",
  },
  line_symbols = {
    add = "+",
    delete = "-",
    change = "~",
  },
}

-- Setup function to be called by the user
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Create highlights based on config
  vim.cmd("highlight default link UnifiedDiffAdd " .. M.config.highlights.add)
  vim.cmd("highlight default link UnifiedDiffDelete " .. M.config.highlights.delete)
  vim.cmd("highlight default link UnifiedDiffChange " .. M.config.highlights.change)

  -- Create namespace if it doesn't exist
  if not M.ns_id then
    M.ns_id = vim.api.nvim_create_namespace("unified_diff")
  end

  -- Ensure sign group exists
  if not M.sign_group_defined then
    M.sign_group_defined = true

    -- Define signs if not already defined
    if vim.fn.sign_getdefined("unified_diff_add")[1] == nil then
      vim.fn.sign_define("unified_diff_add", {
        text = M.config.line_symbols.add,
        texthl = M.config.highlights.add,
      })
    end

    if vim.fn.sign_getdefined("unified_diff_delete")[1] == nil then
      vim.fn.sign_define("unified_diff_delete", {
        text = M.config.line_symbols.delete,
        texthl = M.config.highlights.delete,
      })
    end

    if vim.fn.sign_getdefined("unified_diff_change")[1] == nil then
      vim.fn.sign_define("unified_diff_change", {
        text = M.config.line_symbols.change,
        texthl = M.config.highlights.change,
      })
    end
  end
end

-- Parse diff and return a structured representation
function M.parse_diff(diff_text)
  local lines = vim.split(diff_text, "\n")
  local hunks = {}
  local current_hunk = nil

  for _, line in ipairs(lines) do
    if line:match("^@@") then
      -- Hunk header line like "@@ -1,7 +1,6 @@"
      if current_hunk then
        table.insert(hunks, current_hunk)
      end

      -- Parse line numbers
      local old_start, old_count, new_start, new_count = line:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

      old_count = old_count ~= "" and tonumber(old_count) or 1
      new_count = new_count ~= "" and tonumber(new_count) or 1

      current_hunk = {
        old_start = tonumber(old_start),
        old_count = old_count,
        new_start = tonumber(new_start),
        new_count = new_count,
        lines = {},
      }
    elseif current_hunk and (line:match("^%+") or line:match("^%-") or line:match("^ ")) then
      table.insert(current_hunk.lines, line)
    end
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

-- Display unified diff inline in the buffer
function M.display_inline_diff(buffer, hunks)
  -- Use module namespace if it exists, otherwise create one
  local ns_id = M.ns_id or vim.api.nvim_create_namespace("unified_diff")
  M.ns_id = ns_id

  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)

  -- Clear existing signs
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  -- Define signs in case they aren't defined yet
  if vim.fn.sign_getdefined("unified_diff_add")[1] == nil then
    vim.fn.sign_define("unified_diff_add", {
      text = M.config.line_symbols.add,
      texthl = M.config.highlights.add,
    })
  end

  if vim.fn.sign_getdefined("unified_diff_delete")[1] == nil then
    vim.fn.sign_define("unified_diff_delete", {
      text = M.config.line_symbols.delete,
      texthl = M.config.highlights.delete,
    })
  end

  if vim.fn.sign_getdefined("unified_diff_change")[1] == nil then
    vim.fn.sign_define("unified_diff_change", {
      text = M.config.line_symbols.change,
      texthl = M.config.highlights.change,
    })
  end

  -- Debug info
  vim.api.nvim_echo({ { "Displaying diff with " .. #hunks .. " hunks", "Normal" } }, false, {})

  -- Track if we placed any marks
  local mark_count = 0
  local sign_count = 0

  for _, hunk in ipairs(hunks) do
    local line_idx = hunk.new_start - 1 -- Adjust for 0-indexed lines
    local old_idx = 0
    local new_idx = 0

    -- Debug hunk info
    local hunk_debug = string.format(
      "Hunk: old_start=%d, old_count=%d, new_start=%d, new_count=%d",
      hunk.old_start,
      hunk.old_count,
      hunk.new_start,
      hunk.new_count
    )
    vim.api.nvim_echo({ { hunk_debug, "Normal" } }, false, {})

    for _, line in ipairs(hunk.lines) do
      local first_char = line:sub(1, 1)

      if first_char == " " then
        -- Context line
        line_idx = line_idx + 1
        old_idx = old_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "+" then
        -- Added line
        local line_text = line:sub(2)
        local hl_group = "UnifiedDiffAdd"

        -- Add sign column marker
        local id = line_idx + 1 -- Use line number as ID to avoid duplicates
        local sign_result = vim.fn.sign_place(id, "unified_diff", "unified_diff_add", buffer, {
          lnum = line_idx + 1,
          priority = 10,
        })
        if sign_result > 0 then
          sign_count = sign_count + 1
        end

        -- Only add sign in gutter for added lines, no virtual text overlay
        local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, line_idx, 0, {
          line_hl_group = hl_group,
        })
        if mark_id > 0 then
          mark_count = mark_count + 1
        end

        line_idx = line_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "-" then
        -- Deleted line
        local line_text = line:sub(2)
        local hl_group = "UnifiedDiffDelete"

        -- This is critically important: We need to determine where the deletion happened
        -- and place the virtual text at the PREVIOUS line, not the current line
        -- This is because when a line is deleted, the cursor position is still at
        -- the line after the deletion
        
        -- For indented bullet points, we need to attach the virtual line to the line above
        local attach_line = line_idx
        
        -- If we're at the end of the buffer, attach to the previous line
        if line_idx >= vim.api.nvim_buf_line_count(buffer) then
          attach_line = line_idx - 1
        end
        
        -- Add sign in gutter AND virtual line in one extmark at the end of the previous line
        local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, attach_line, 0, {
          sign_text = M.config.line_symbols.delete,
          sign_hl_group = "UnifiedDiffDelete",
          virt_lines = { { { line_text, hl_group } } },
          virt_lines_above = true, -- Place virtual line ABOVE the current position
        })
        if mark_id > 0 then
          mark_count = mark_count + 1
        end

        old_idx = old_idx + 1
      end
    end
  end

  -- Debug summary
  vim.api.nvim_echo({ { "Placed " .. mark_count .. " extmarks and " .. sign_count .. " signs", "Normal" } }, false, {})

  -- Return success based on whether we placed any marks
  return mark_count > 0
end

-- Check if file is in a git repository
function M.is_git_repo(file_path)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  local cmd = string.format("cd %s && git rev-parse --is-inside-work-tree 2>/dev/null", vim.fn.shellescape(dir))
  local result = vim.fn.system(cmd)
  return vim.trim(result) == "true"
end

-- Get file content from the last git commit
function M.get_git_file_content(file_path)
  local relative_path = vim.fn.system(
    string.format(
      "cd %s && git ls-files --full-name %s | tr -d '\n'",
      vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h")),
      vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":t"))
    )
  )

  -- If file isn't tracked, return nil
  if relative_path == "" then
    return nil
  end

  -- Try to get file from the last commit
  local cmd = string.format(
    "cd %s && git show HEAD:%s 2>/dev/null",
    vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h")),
    vim.fn.shellescape(relative_path)
  )

  local content = vim.fn.system(cmd)

  -- Check if command succeeded
  if vim.v.shell_error ~= 0 then
    return nil
  end

  return content
end

-- Show diff of the current buffer compared to git HEAD
function M.show_git_diff()
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
    vim.api.nvim_echo({ { "File is not in a git repository, falling back to buffer diff", "WarningMsg" } }, false, {})
    return M.show_buffer_diff()
  end

  -- Get content from git
  local git_content = M.get_git_file_content(file_path)

  -- If file isn't in git yet, fall back to buffer diff
  if not git_content then
    vim.api.nvim_echo({ { "File not found in git history, falling back to buffer diff", "WarningMsg" } }, false, {})
    return M.show_buffer_diff()
  end

  -- Check if there are any changes at all
  if current_content == git_content then
    vim.api.nvim_echo({ { "No changes detected between buffer and git version", "WarningMsg" } }, false, {})
    return false
  end

  -- Create temporary files for diffing
  local temp_current = vim.fn.tempname()
  local temp_git = vim.fn.tempname()

  vim.fn.writefile(vim.split(current_content, "\n"), temp_current)
  vim.fn.writefile(vim.split(git_content, "\n"), temp_git)

  -- Debug
  vim.api.nvim_echo(
    { { "Current content length: " .. #current_content .. ", Git content length: " .. #git_content, "Normal" } },
    false,
    {}
  )

  -- Get diff output
  local diff_cmd = string.format("diff -u %s %s", temp_git, temp_current)
  local diff_output = vim.fn.system(diff_cmd)

  -- Debug diff command and output
  vim.api.nvim_echo({ { "Diff command: " .. diff_cmd, "Normal" } }, false, {})
  vim.api.nvim_echo({ { "Diff output length: " .. #diff_output, "Normal" } }, false, {})

  -- Clean up temp files
  vim.fn.delete(temp_current)
  vim.fn.delete(temp_git)

  if diff_output ~= "" then
    vim.api.nvim_echo({ { "Parsing diff output...", "Normal" } }, false, {})
    local hunks = M.parse_diff(diff_output)
    vim.api.nvim_echo({ { "Found " .. #hunks .. " hunks", "Normal" } }, false, {})

    local result = M.display_inline_diff(buffer, hunks)
    return result
  else
    vim.api.nvim_echo({ { "No differences found by diff command", "WarningMsg" } }, false, {})
  end

  return false
end

-- Removed show_buffer_diff function - git diff only

-- Show diff (always use git diff)
function M.show_diff()
  return M.show_git_diff()
end

-- Toggle diff display
function M.toggle_diff()
  local buffer = vim.api.nvim_get_current_buf()
  local ns_id = M.ns_id or vim.api.nvim_create_namespace("unified_diff")
  M.ns_id = ns_id

  -- Check if diff is already displayed
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})

  if #marks > 0 then
    -- Clear diff display
    vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
    vim.fn.sign_unplace("unified_diff", { buffer = buffer })
    vim.api.nvim_echo({ { "Diff display cleared", "Normal" } }, false, {})
  else
    -- Show diff based on config
    local result = M.show_diff()
    if not result then
      vim.api.nvim_echo({ { "Failed to display diff", "ErrorMsg" } }, false, {})
    end
  end
end

return M
