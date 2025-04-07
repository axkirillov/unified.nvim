-- Module for handling user actions within the file tree buffer

local tree_state_module = require("unified.file_tree.state")
local tree_state = tree_state_module.tree_state
local render = require("unified.file_tree.render")
local global_state = require("unified.state") -- For accessing main window

local M = {}

-- Helper to check if the current buffer is the file tree buffer
local function is_file_tree_buffer()
  return vim.api.nvim_get_current_buf() == tree_state.buffer
end

-- Helper function to open a file node in the main window and show diff
local function open_file_node(node)
  if not node or node.is_dir then
    return -- Only open files
  end

  local win = global_state.get_main_window() -- Use global state module
  if win and vim.api.nvim_win_is_valid(win) then
    -- Switch to the target window and use standard edit
    local current_win = vim.api.nvim_get_current_win() -- Store current window
    vim.api.nvim_set_current_win(win) -- Switch to the main/target window
    vim.cmd("edit " .. vim.fn.fnameescape(node.path)) -- Open the file
    -- Show diff for the newly opened file using the plugin's potential internal logic
    -- Use lazy loading via package.loaded to avoid circular dependency
    local unified_module = package.loaded["unified"]
    if unified_module then
      -- Check if the main unified view needs activation or just a refresh
      if not global_state.is_active then
        if unified_module.activate then
          unified_module.activate() -- Activate the diff view
        end
      else
        -- If already active, refresh the diff display for the new file
        if unified_module.show_diff then
          unified_module.show_diff() -- Will use the current commit_base from global_state
        end
      end
    end

    -- Switch focus back to the original window (file tree)
    vim.api.nvim_set_current_win(current_win)
    -- Keep the commented out line if it was there, or remove if not needed
    -- vim.api.nvim_set_current_win(current_win)
    -- Show diff for the newly opened file
    -- Use lazy loading via package.loaded to avoid circular dependency
    local unified_module = package.loaded["unified"]
    if not unified_module then
      return -- Should ideally be loaded by now
    end

    if not global_state.is_active then
      if unified_module.activate then
        unified_module.activate() -- Activate the diff view
      end
    else
      -- If already active, refresh the diff display for the new file
      if unified_module.show_diff then
        unified_module.show_diff() -- Will use the current commit_base from global_state
      end
    end
  end
end

-- Open file under cursor (previously toggle_node)
function M.toggle_node()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = tree_state.line_to_node[line]

  if not node then
    return
  end

  -- Call the helper function to open the file
  open_file_node(node)
end

-- Expand node
function M.expand_node()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = tree_state.line_to_node[line]

  -- Expansion is now automatic via render, this action is no longer needed.
end

-- Collapse node or go to parent
function M.collapse_node()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = tree_state.line_to_node[line]

  if not node then
    return
  end

  -- Collapse is no longer needed. Only handle going to parent.
  if node.parent and node.parent ~= tree_state.current_tree.root then
    -- If not an expanded directory, or it's a file, try to go to parent
    M.go_to_parent()
  end
end

-- Refresh the tree
function M.refresh()
  if not is_file_tree_buffer() then
    return
  end

  -- Re-create the tree with the same settings stored in state
  local root_path = tree_state.root_path
  local diff_only = tree_state.diff_only
  local commit_ref = global_state.get_commit_base() -- Get current commit base

  if root_path then
    -- Need to call the main function to recreate buffer and tree logic
    -- This requires access to the function that will be in init.lua
    local unified_file_tree_module = package.loaded["unified.file_tree"]
    if unified_file_tree_module and unified_file_tree_module.create_file_tree_buffer then
      -- Create a new buffer/tree instance
      local new_buf = unified_file_tree_module.create_file_tree_buffer(root_path, diff_only, commit_ref)
      if new_buf and tree_state.window and vim.api.nvim_win_is_valid(tree_state.window) then
        -- Replace the buffer in the existing window
        vim.api.nvim_win_set_buf(tree_state.window, new_buf)
        -- The create function should update tree_state.buffer internally
      end
    end
  end
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

  local help_win = vim.api.nvim_open_win(help_buf, true, win_opts)

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
  local node = tree_state.line_to_node[line]

  if not node or not node.parent or node.parent == tree_state.current_tree.root then
    -- Don't go above the root shown in the tree
    return
  end

  -- Find the parent node's line
  local parent_line = nil
  for l, n in pairs(tree_state.line_to_node) do
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
  if tree_state.window and vim.api.nvim_win_is_valid(tree_state.window) then
    vim.api.nvim_win_close(tree_state.window, true)
  end
  -- Reset state after closing
  tree_state_module.reset_state()
  -- Also reset the global active state if the main plugin relies on the tree being open
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
  local total_lines = vim.api.nvim_buf_line_count(tree_state.buffer)
  local next_line = current_line

  for i = 1, total_lines do -- Iterate at most total_lines times
    next_line = (next_line + direction + total_lines) % total_lines -- Wrap around

    local node = tree_state.line_to_node[next_line]
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
