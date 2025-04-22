local M = {}

local function is_file_tree_buffer()
  local state = require("unified.file_tree.state")
  return vim.api.nvim_get_current_buf() == state.buffer
end

local function open_file_node(node)
  if not node or node.is_dir then
    return
  end

  local state = require("unified.state")
  local win = state.get_main_window()
  if not win or not vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_echo({ { "No main window", "WarningMsg" } }, false, {})
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)

  vim.defer_fn(function()
    local target_path = vim.fn.fnameescape(node.path)
    local target_buf_id = vim.fn.bufadd(target_path)
    vim.fn.bufload(target_buf_id)

    if not vim.api.nvim_buf_is_valid(target_buf_id) then
      vim.api.nvim_echo({ { "Failed to load buffer for: " .. node.path, "ErrorMsg" } }, false, {})
      vim.api.nvim_set_current_win(current_win)
      return
    end
    vim.api.nvim_win_set_buf(win, target_buf_id)

    local diff = require("unified.diff")
    local commit = state.get_commit_base()
    if not commit then
      vim.api.nvim_echo({ { "No commit base set", "WarningMsg" } }, false, {})
      vim.api.nvim_set_current_win(current_win)
      return
    end

    diff.show(commit, target_buf_id)
    local auto_refresh = require("unified.auto_refresh")
    auto_refresh.setup(target_buf_id)

    if vim.api.nvim_win_is_valid(current_win) then
      vim.api.nvim_set_current_win(current_win)
    end
  end, 1)
end

-- Open file under cursor (previously toggle_node)
function M.toggle_node()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local state = require("unified.file_tree.state")
  local node = state.line_to_node[line]

  if not node then
    return
  end

  -- Call the helper function to open the file
  open_file_node(node)
end

function M.refresh()
  if not is_file_tree_buffer() then
    return
  end

  local state = require("unified.file_tree.state")
  local diff_only = state.diff_only
  local commit_ref = state.commit_ref

  local file_tree = require("unified.file_tree")
  local new_buf = file_tree.create_file_tree_buffer(state.root_path, diff_only, commit_ref)
  vim.api.nvim_win_set_buf(state.window, new_buf)
end

-- Show help dialog
function M.show_help()
  if not is_file_tree_buffer() then
    return
  end

  local help_text = {
    "Unified File Explorer Help",
    "------------------------",
    "",
    "Navigation:",
    "  j/k       : Move up/down",
    "  h/l       : Collapse/expand directory",
    "  <CR>      : Toggle directory or open file",
    "  <C-j>     : Same as Enter",
    "  -         : Go to parent directory",
    "",
    "Actions:",
    "  R         : Refresh the tree",
    "  q         : Close the tree",
    "  ?         : Show this help",
    "",
    "File Status:",
    "  M         : Modified",
    "  A         : Added",
    "  D         : Deleted",
    "  R         : Renamed",
    "  C         : Copied / In Commit",
    "  ?         : Untracked",
    "",
    "Press any key to close this help",
  }

  -- Create a temporary floating window
  local win_width = math.max(40, math.floor(vim.o.columns / 3))
  local win_height = #help_text

  local win_opts = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = math.floor((vim.o.lines - win_height) / 2),
    col = math.floor((vim.o.columns - win_width) / 2),
    style = "minimal",
    border = "rounded",
  }

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_text)

  local _ = vim.api.nvim_open_win(help_buf, true, win_opts)

  -- Set buffer options
  vim.bo[help_buf].modifiable = false
  vim.bo[help_buf].bufhidden = "wipe"

  -- Add highlighting
  local ns_id = vim.api.nvim_create_namespace("unified_help")
  vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(help_buf, ns_id, "NonText", 1, 0, -1)

  -- Highlight section headers
  for i, line in ipairs(help_text) do
    if line:match("^[A-Za-z]") and line:match(":$") then
      vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Statement", i - 1, 0, -1)
    end
    -- Highlight keys
    if line:match("^  [^:]+:") then
      local key_end = line:find(":")
      if key_end then
        vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Special", i - 1, 2, key_end)
      end
    end
  end

  -- Close on any key press
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Space>", "<cmd>close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(help_buf, "n", "q", "<cmd>close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<CR>", "<cmd>close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Esc>", "<cmd>close<CR>", { silent = true, noremap = true })
end

-- Go to parent directory node
function M.go_to_parent()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local state = require("unified.file_tree.state")
  local node = state.line_to_node[line]

  if not node or not node.parent or node.parent == state.current_tree.root then
    -- Don't go above the root shown in the tree
    return
  end

  -- Find the parent node's line
  local parent_line = nil
  for l, n in pairs(state.line_to_node) do
    if n == node.parent then
      parent_line = l
      break
    end
  end

  if parent_line then
    vim.api.nvim_win_set_cursor(0, { parent_line + 1, 0 })
  end
end

-- Close the file tree window
function M.close_tree()
  local state = require("unified.file_tree.state")
  if state.window and vim.api.nvim_win_is_valid(state.window) then
    vim.api.nvim_win_close(state.window, true)
  end
  -- Reset state after closing
  state.reset_state()
  -- Also reset the global active state if the main plugin relies on the tree being open
  local global_state = require("unified.state")
  global_state.is_active = false
  global_state.file_tree_win = nil
  global_state.file_tree_buf = nil
end -- End of M.close_tree

-- Move cursor to the next/previous file node and open it
function M.move_cursor_and_open_file(direction)
  if not is_file_tree_buffer() then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
  local state = require("unified.file_tree.state")
  local total_lines = vim.api.nvim_buf_line_count(state.buffer)
  local next_line = current_line

  for _ = 1, total_lines do -- Iterate at most total_lines times
    next_line = (next_line + direction + total_lines) % total_lines -- Wrap around

    local node = state.line_to_node[next_line]
    if node and not node.is_dir then
      -- Found the next file node
      vim.api.nvim_win_set_cursor(0, { next_line + 1, 0 }) -- Set cursor (1-based)
      open_file_node(node) -- Open the file
      return -- Done
    end
  end
  -- If no file node found after full loop (unlikely in a populated tree), do nothing
end -- End of M.move_cursor_and_open_file

M.open_file_node = open_file_node -- Expose for use in init.lua

return M
