-- Deleted lines are rendered as virtual lines, and Neovim always draws virtual lines
-- from column 0: when a window is scrolled horizontally ('nowrap'), the buffer lines
-- move but the deleted lines stay put, truncated at the window edge.
--
-- This module keeps the original text of every deleted-lines extmark and, whenever a
-- window scrolls sideways, rewrites those extmarks so their text starts at the window's
-- current 'leftcol'. The deleted lines then move together with the rest of the diff.
local M = {}

local config = require("unified.config")

-- originals[buffer][mark_id] = { lines = { text, ... }, above = boolean }
local originals = {}

-- The 'leftcol' each window was last synced to, so a WinScrolled that only moved
-- vertically costs nothing.
local synced_leftcol = {}

-- The part of `text` from display column `col` onwards. Walks characters rather than
-- bytes so tabs and double-width characters land on the right column.
local function from_display_column(text, col)
  if col <= 0 then
    return text
  end

  local width = 0
  local char_count = vim.fn.strchars(text)

  for i = 0, char_count - 1 do
    if width >= col then
      return vim.fn.strcharpart(text, i)
    end
    width = width + vim.fn.strdisplaywidth(vim.fn.strcharpart(text, i, 1))
  end

  return ""
end

-- Pad `text` with spaces up to `width` display columns so the highlight runs to the
-- window edge, matching how the lines are rendered initially.
local function pad_to(text, width)
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width < width then
    return text .. string.rep(" ", width - display_width)
  end
  return text
end

--- Remember the original text of a deleted-lines extmark so it can be re-sliced later.
---@param buffer integer
---@param mark_id integer
---@param lines string[] The deleted lines, unpadded
---@param above boolean The extmark's `virt_lines_above`
function M.remember(buffer, mark_id, lines, above)
  originals[buffer] = originals[buffer] or {}
  originals[buffer][mark_id] = { lines = lines, above = above }
end

--- Forget everything remembered for a buffer (its diff was cleared or re-rendered).
---@param buffer integer
function M.forget(buffer)
  originals[buffer] = nil
end

--- Rewrite the deleted lines shown in `win` so they start at its current 'leftcol'.
---@param win integer
function M.sync(win)
  if not vim.api.nvim_win_is_valid(win) then
    synced_leftcol[win] = nil
    return
  end

  local buffer = vim.api.nvim_win_get_buf(win)
  local marks = originals[buffer]
  if not marks then
    return
  end

  local leftcol = vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview().leftcol
  end)
  if synced_leftcol[win] == leftcol then
    return
  end
  synced_leftcol[win] = leftcol

  local width = vim.api.nvim_win_get_width(win)
  local ns_id = config.ns_id

  for mark_id, original in pairs(marks) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buffer, ns_id, mark_id, {})

    if #pos == 0 then
      -- The diff was re-rendered and this mark no longer exists.
      marks[mark_id] = nil
    else
      local virt_lines = {}
      for _, text in ipairs(original.lines) do
        local visible = pad_to(from_display_column(text, leftcol), width)
        table.insert(virt_lines, { { visible, "UnifiedDiffDelete" } })
      end

      vim.api.nvim_buf_set_extmark(buffer, ns_id, pos[1], pos[2], {
        id = mark_id,
        virt_lines = virt_lines,
        virt_lines_above = original.above,
      })
    end
  end
end

--- Sync every window currently showing a buffer with remembered deleted lines.
function M.sync_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if originals[vim.api.nvim_win_get_buf(win)] then
      M.sync(win)
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("unified_virt_scroll", { clear = true })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = M.sync_all,
    desc = "Scroll deleted lines horizontally with the buffer",
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      M.forget(event.buf)
    end,
  })
end

return M
