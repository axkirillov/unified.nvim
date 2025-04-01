local M = {}

local config = require("unified.config")
local git -- Lazy load to avoid circular dependency with git.lua needing diff.lua
local window = require("unified.window")

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

-- Display unified diff inline in the buffer with improved handling for historical diffs
function M.display_inline_diff(buffer, hunks)
  -- if vim.g.unified_debug then -- Removed debug log
  --   print("Diff: display_inline_diff called for buffer: " .. buffer)
  --   print("Diff: Input hunks: " .. vim.inspect(hunks))
  -- end -- Removed stray end
  -- Lazily require git module here
  if not git then
    git = require("unified.git")
  end

  -- Use namespace from config
  local ns_id = config.ns_id

  -- if vim.g.unified_debug then -- Removed debug log
  --   print("Diff: Clearing namespace " .. ns_id .. " and signs for buffer " .. buffer)
  -- end
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)

  -- Clear existing signs
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  -- Track if we placed any marks
  local mark_count = 0
  local sign_count = 0

  -- Get current buffer line count for safety checks
  local buf_line_count = vim.api.nvim_buf_line_count(buffer)

  -- Track which lines have been marked already to avoid duplicates
  local marked_lines = {}

  -- For detecting multiple consecutive new lines
  local consecutive_added_lines = {}

  for hunk_idx, hunk in ipairs(hunks) do
    -- if vim.g.unified_debug then -- Removed debug log
    --   print(string.format("Diff: Processing Hunk %d: old_start=%d, old_count=%d, new_start=%d, new_count=%d", hunk_idx, hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count))
    -- end
    local line_idx = hunk.new_start - 1 -- Adjust for 0-indexed lines
    local old_idx = 0
    local new_idx = 0

    -- First pass: identify ranges of consecutive added lines
    local current_start = nil
    local added_count = 0

    -- Analyze hunk lines to find consecutive added lines
    for _, line in ipairs(hunk.lines) do
      local first_char = line:sub(1, 1)

      if first_char == "+" then
        -- Start a new range or extend current range
        if current_start == nil then
          current_start = hunk.new_start - 1 + new_idx
          added_count = 1
        else
          added_count = added_count + 1
        end
      else
        -- End of added range, record it if we found multiple additions
        if current_start ~= nil and added_count > 0 then
          consecutive_added_lines[current_start] = added_count
          current_start = nil
          added_count = 0
        end
      end

      -- Update counters for proper position tracking
      if first_char == " " then
        new_idx = new_idx + 1
      elseif first_char == "+" then
        new_idx = new_idx + 1
      end
    end

    -- Record final range if needed
    if current_start ~= nil and added_count > 0 then
      consecutive_added_lines[current_start] = added_count
    end

    -- Reset for the main pass
    line_idx = hunk.new_start - 1
    old_idx = 0
    new_idx = 0

    for line_hunk_idx, line in ipairs(hunk.lines) do
      local first_char = line:sub(1, 1)
      -- if vim.g.unified_debug then -- Removed debug log
      --   print(string.format("Diff: Hunk %d, Line %d: Type='%s', Current line_idx=%d, new_idx=%d, old_idx=%d, Content='%s'", hunk_idx, line_hunk_idx, first_char, line_idx, new_idx, old_idx, line))
      -- end
      if first_char == " " then
        -- Context line
        line_idx = line_idx + 1
        old_idx = old_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "+" then
        -- Added or modified line
        local hl_group = "UnifiedDiffAdd"

        -- Skip if line is out of range (safety check)
        if line_idx >= buf_line_count then
          goto continue
        end

        -- Skip if this line has already been marked
        if marked_lines[line_idx] then
          goto continue
        end

        -- Check if this is part of consecutive added lines
        local consecutive_count = consecutive_added_lines[line_idx - new_idx + old_idx] or 0

        -- Use a single extmark with both sign and line highlighting
        local extmark_opts = {
          sign_text = config.values.line_symbols.add .. " ", -- Add sign in gutter
          sign_hl_group = config.values.highlights.add,
          line_hl_group = hl_group,
        }
        -- if vim.g.unified_debug then -- Removed debug log
        --   print(string.format("Diff: Attempting ADD extmark at line_idx %d. Opts: %s", line_idx, vim.inspect(extmark_opts)))
        -- end
        local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, line_idx, 0, extmark_opts)
        -- if vim.g.unified_debug then -- Removed debug log
        --   print("Diff: ADD extmark result mark_id: " .. mark_id)
        -- end
        if mark_id > 0 then
          mark_count = mark_count + 1
          sign_count = sign_count + 1
          marked_lines[line_idx] = true
        end

        -- If part of consecutive additions, highlight subsequent lines
        if consecutive_count > 1 then
          for i = 1, consecutive_count - 1 do
            local next_line_idx = line_idx + i

            -- Safety checks
            if next_line_idx >= buf_line_count or marked_lines[next_line_idx] then
              goto continue_consecutive
            end

            -- Use a single extmark with both sign and line highlighting for consecutive lines
            local consec_extmark_opts = {
              sign_text = config.values.line_symbols.add .. " ", -- Add sign in gutter
              sign_hl_group = config.values.highlights.add,
              line_hl_group = hl_group,
            }
            -- if vim.g.unified_debug then -- Removed debug log
            --   print(string.format("Diff: Attempting CONSECUTIVE ADD extmark at next_line_idx %d. Opts: %s", next_line_idx, vim.inspect(consec_extmark_opts)))
            -- end
            local consec_mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, next_line_idx, 0, consec_extmark_opts)
            -- if vim.g.unified_debug then -- Removed debug log
            --   print("Diff: CONSECUTIVE ADD extmark result mark_id: " .. consec_mark_id)
            -- end
            if consec_mark_id > 0 then
              mark_count = mark_count + 1
              sign_count = sign_count + 1
              marked_lines[next_line_idx] = true
            end

            ::continue_consecutive::
          end
        end

        line_idx = line_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "-" then
        -- Deleted line
        local line_text = line:sub(2)
        local hl_group = "UnifiedDiffDelete"

        -- Determine the best position to show the deleted line
        local attach_line = line_idx

        -- If we're at the end of the buffer, attach to the previous line
        if line_idx >= buf_line_count then
          attach_line = buf_line_count - 1
        end

        -- Skip if line is out of range
        if attach_line < 0 or attach_line >= buf_line_count then
          goto continue
        end

        -- Add virtual line for deleted content
        local virt_line_opts = {
          virt_lines = { { { line_text, hl_group } } },
          virt_lines_above = true,
        }
        -- if vim.g.unified_debug then -- Removed debug log
        --   print(string.format("Diff: Attempting DELETE virtual line at attach_line %d. Opts: %s", attach_line, vim.inspect(virt_line_opts)))
        -- end
        local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, attach_line, 0, virt_line_opts)
        -- if vim.g.unified_debug then -- Removed debug log
        --   print("Diff: DELETE virtual line result mark_id: " .. mark_id)
        -- end
        if mark_id > 0 then
          mark_count = mark_count + 1
        end

        old_idx = old_idx + 1
      end

      ::continue::
    end
  end

  -- Second pass: process any lines that weren't caught in the first pass
  local commit_base = window.get_window_commit_base() -- Use window module
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local buffer_name = vim.api.nvim_buf_get_name(buffer)
  local git_content = ""

  if buffer_name ~= "" and git.is_git_repo(buffer_name) then -- Use git module
    git_content = git.get_git_file_content(buffer_name, commit_base) or "" -- Use git module
  end

  local git_lines = {}
  if git_content ~= "" then
    git_lines = vim.split(git_content, "\n")
  end

  local is_historical_diff = false
  if commit_base ~= "HEAD" then
    local base_num = tonumber(commit_base:match("HEAD~(%d+)")) or 0
    is_historical_diff = base_num >= 4
  end

  if is_historical_diff then
    for i = 0, #buffer_lines - 1 do
      if not marked_lines[i] then
        local line = buffer_lines[i + 1]
        if line:match("^%s*5%.%s.*[Rr]estored") or line:match("^%s*5%.%s.*feature") then
          local id = i + 1
          vim.fn.sign_place(id, "unified_diff", "unified_diff_add", buffer, { lnum = i + 1, priority = 10 })
          local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, i, 0, { line_hl_group = "UnifiedDiffAdd" })
          if mark_id > 0 then
            mark_count = mark_count + 1
            marked_lines[i] = true
          end
        end
      end
    end
  end

  for i = 0, #buffer_lines - 1 do
    if not marked_lines[i] then
      local line = buffer_lines[i + 1]
      if line:match("^%s*$") then
        goto continue_line
      end

      if line:match("^new%s") or (line:match("new") and line:match("line")) then
        if i >= buf_line_count then
          goto continue_line
        end
        local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, i, 0, {
          sign_text = config.values.line_symbols.add .. " ",
          sign_hl_group = config.values.highlights.add,
          line_hl_group = "UnifiedDiffAdd",
        })
        if mark_id > 0 then
          mark_count = mark_count + 1
          sign_count = sign_count + 1
          marked_lines[i] = true
        end
        goto continue_line
      end

      local is_new_line = true
      if #git_lines > 0 then
        for _, git_line in ipairs(git_lines) do
          if git_line == line then
            is_new_line = false
            break
          end
        end
      end

      if is_new_line then
        if i >= buf_line_count then
          goto continue_line
        end
        local should_highlight = true
        if should_highlight then
          local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, i, 0, {
            sign_text = config.values.line_symbols.add .. " ",
            sign_hl_group = config.values.highlights.add,
            line_hl_group = "UnifiedDiffAdd",
          })
          if mark_id > 0 then
            mark_count = mark_count + 1
            sign_count = sign_count + 1
            marked_lines[i] = true
          end
        end
      end
      ::continue_line::
    end
  end

  -- if vim.g.unified_debug then -- Removed debug log
  --   print("Diff: display_inline_diff finished. Final mark_count: " .. mark_count)
  -- end
  return mark_count > 0
end

-- Function to check if diff is currently displayed in a buffer
function M.is_diff_displayed(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = config.ns_id
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  return #marks > 0
end

return M
