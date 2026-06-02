local hunk_store = require("unified.hunk_store")

local function jump(forward)
  local hunks = hunk_store.get(vim.api.nvim_get_current_buf())
  if not hunks or #hunks == 0 then
    vim.api.nvim_echo({ { "No hunks to navigate.", "WarningMsg" } }, false, {})
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local choose = forward and math.min or math.max
  local target

  for _, l in ipairs(hunks) do
    if (forward and l > cursor) or (not forward and l < cursor) then
      target = choose(target or l, l)
    end
  end

  if not target then
    target = forward and hunks[1] or hunks[#hunks]
  end

  vim.api.nvim_win_set_cursor(0, { target, 0 })
  vim.cmd.normal({ "zz", bang = true })
end

local M = {}

function M.next_hunk()
  jump(true)
end

function M.previous_hunk()
  jump(false)
end

-- Move `win`'s cursor to the first changed hunk in `buf` and center the view.
-- `win`/`buf` default to the current window/buffer; passing an explicit window
-- lets callers scroll a buffer shown elsewhere (e.g. the tree scrolling the main
-- window) without stealing focus. No-op when the buffer has no hunks. This is a
-- plain primitive: callers gate it on the `jump_to_first_hunk` option.
function M.jump_to_first_hunk(win, buf)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  buf = buf or vim.api.nvim_win_get_buf(win)
  local hunks = hunk_store.get(buf)
  if not hunks or #hunks == 0 then
    return
  end
  local target = math.min(hunks[1], vim.api.nvim_buf_line_count(buf))
  pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
  pcall(vim.api.nvim_win_call, win, function()
    vim.cmd.normal({ "zz", bang = true })
  end)
end

return M
