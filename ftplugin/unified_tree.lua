vim.bo.modifiable = false
vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.bufhidden = "wipe"
vim.bo.syntax = "unified_tree"

vim.wo.cursorline = true
vim.wo.statusline = "File Explorer"
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.winfixwidth = true
vim.wo.foldenable = false
vim.wo.list = false
vim.wo.wrap = false

-- Local fallback to avoid errors if an older cached version of actions.lua is loaded
local function unified_move_cursor_file_only(direction, count)
  local ok, actions = pcall(require, 'unified.file_tree.actions')
  if ok and type(actions.move_cursor_file_only) == 'function' then
    return actions.move_cursor_file_only(direction, count)
  end

  -- Fallback implementation if the function is not available yet
  local state_ok, tree_state = pcall(require, 'unified.file_tree.state')
  if not state_ok then
    return
  end
  if vim.api.nvim_get_current_buf() ~= tree_state.buffer then
    return
  end
  if not tree_state.buffer or not vim.api.nvim_buf_is_valid(tree_state.buffer) then
    return
  end

  local total_lines = vim.api.nvim_buf_line_count(tree_state.buffer)
  if not total_lines or total_lines < 1 then
    return
  end

  local dir = (direction == -1) and -1 or 1
  local cnt = tonumber(count) or 1

  local current = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
  for _ = 1, cnt do
    local next_line = current
    for _i = 1, total_lines do
      next_line = (next_line + dir + total_lines) % total_lines
      local node = tree_state.line_to_node[next_line]
      if node and not node.is_dir then
        current = next_line
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(0, { current + 1, 0 })
end

vim.keymap.set("n", "j", function()
  unified_move_cursor_file_only(1, vim.v.count1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "k", function()
  unified_move_cursor_file_only(-1, vim.v.count1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "<Down>", function()
  unified_move_cursor_file_only(1, vim.v.count1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "<Up>", function()
  unified_move_cursor_file_only(-1, vim.v.count1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "R",
  function()
    require('unified.file_tree.actions').refresh()
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "q",
  function()
    require('unified.file_tree.actions').close_tree()
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "?",
  function()
    require('unified.file_tree.actions').show_help()
  end,
  { noremap = true, silent = true, buffer = true }
)

vim.keymap.set("n", "l",
  function()
    require('unified.file_tree.actions').toggle_node()
  end,
  { noremap = true, silent = true, buffer = true }
)
