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

return M
