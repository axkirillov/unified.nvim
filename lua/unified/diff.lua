local M = {}

local config = require("unified.config")
local hunk_store = require("unified.hunk_store")

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

function M.display_deleted_file(buffer, blob_text)
  local ns_id = config.ns_id
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  local lines = vim.split(blob_text, "\n", { plain = true })
  local was_modifiable = vim.bo[buffer].modifiable
  local was_readonly = vim.bo[buffer].readonly

  if not was_modifiable then
    vim.bo[buffer].modifiable = true
  end
  if was_readonly then
    vim.bo[buffer].readonly = false
  end

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  vim.bo[buffer].modified = false
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].readonly = true

  for i = 0, #lines - 1 do
    vim.api.nvim_buf_set_extmark(buffer, ns_id, i, 0, {
      line_hl_group = "UnifiedDiffDelete",
    })
  end

  vim.bo[buffer].readonly = true
end

function M.display_inline_diff(buffer, hunks)
  local ns_id = config.ns_id

  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)

  -- Clear existing signs
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  local new_hunk_lines = {}

  -- Track if we placed any marks
  local mark_count = 0
  local sign_count = 0

  -- Get current buffer line count for safety checks
  local buf_line_count = vim.api.nvim_buf_line_count(buffer)

  -- Track which lines have been marked already to avoid duplicates
  local marked_lines = {}

  -- For detecting multiple consecutive new lines
  local consecutive_added_lines = {}

  local in_changed_block = false

  for _, hunk in ipairs(hunks) do
    local line_idx = math.max(hunk.new_start - 1, 0)
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
    in_changed_block = false

    for _, line in ipairs(hunk.lines) do
      local first_char = line:sub(1, 1)

      if first_char == "+" or first_char == "-" then
        if not in_changed_block then
          table.insert(new_hunk_lines, line_idx + 1)
          in_changed_block = true
        end
      else
        in_changed_block = false
      end

      if first_char == " " then
        -- Context line
        line_idx = line_idx + 1
        old_idx = old_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "+" then
        -- Added or modified line
        local hl_group = "UnifiedDiffAdd"

        -- Process only if line is within range and not already marked
        if line_idx < buf_line_count and not marked_lines[line_idx] then
          -- Check if this is part of consecutive added lines
          local consecutive_count = consecutive_added_lines[line_idx - new_idx + old_idx] or 0

          -- Use a single extmark with both sign and line highlighting
          local extmark_opts = {
            sign_text = config.values.line_symbols.add .. " ", -- Add sign in gutter
            sign_hl_group = config.values.highlights.add,
            line_hl_group = hl_group,
          }
          local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, line_idx, 0, extmark_opts)
          if mark_id > 0 then
            mark_count = mark_count + 1
            sign_count = sign_count + 1
            marked_lines[line_idx] = true

            -- If part of consecutive additions, highlight subsequent lines
            if consecutive_count > 1 then
              for i = 1, consecutive_count - 1 do
                local next_line_idx = line_idx + i

                -- Process only if next line is within range and not already marked
                if next_line_idx < buf_line_count and not marked_lines[next_line_idx] then
                  -- Use a single extmark with both sign and line highlighting for consecutive lines
                  local consec_extmark_opts = {
                    sign_text = config.values.line_symbols.add .. " ", -- Add sign in gutter
                    sign_hl_group = config.values.highlights.add,
                    line_hl_group = hl_group,
                  }
                  local consec_mark_id =
                    vim.api.nvim_buf_set_extmark(buffer, ns_id, next_line_idx, 0, consec_extmark_opts)
                  if consec_mark_id > 0 then
                    mark_count = mark_count + 1
                    sign_count = sign_count + 1
                    marked_lines[next_line_idx] = true
                  end
                end
              end
            end
          end
        end

        line_idx = line_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "-" then
        local line_text = line:sub(2)
        local hl_group = "UnifiedDiffDelete"

        local attach_line = math.max(line_idx, 0)
        local show_above = attach_line > 0

        if line_idx >= buf_line_count then
          attach_line = buf_line_count - 1
        end

        if attach_line < buf_line_count then
          local virt_line_opts = {
            virt_lines = { { { line_text, hl_group } } },
            virt_lines_above = show_above,
          }
          local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, attach_line, 0, virt_line_opts)
          if mark_id > 0 then
            mark_count = mark_count + 1
          end
        end

        old_idx = old_idx + 1
      end
    end
  end

  if #new_hunk_lines > 0 then
    table.sort(new_hunk_lines)
    local unique_lines = { new_hunk_lines[1] }
    for i = 2, #new_hunk_lines do
      if new_hunk_lines[i] > unique_lines[#unique_lines] then
        table.insert(unique_lines, new_hunk_lines[i])
      end
    end
    hunk_store.set(buffer, unique_lines)
  else
    hunk_store.clear(buffer)
  end
  return mark_count > 0
end

-- Function to check if diff is currently displayed in a buffer
function M.is_diff_displayed(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = config.ns_id
  local marks = vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, {})
  return #marks > 0
end

---@param commit string
---@param buffer_id? integer Optional buffer ID to show diff in. Defaults to current buffer.
function M.show(commit, buffer_id)
  local buffer = buffer_id or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_echo({ { "Invalid buffer provided to diff.show", "ErrorMsg" } }, false, {})
    return false
  end

  local ft = vim.api.nvim_buf_get_option(buffer, "filetype")

  if ft == "unified_tree" then
    return false
  end

  local git = require("unified.git")
  return git.show_git_diff_against_commit(commit, buffer)
end

function M.show_current(commit)
  if not commit then
    local state = require("unified.state")
    local ok
    ok, commit = pcall(state.get_commit_base)
    commit = ok and commit or "HEAD"
  end

  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  if ft == "unified_tree" then
    return false
  end

  return M.show(commit, buf)
end

return M
