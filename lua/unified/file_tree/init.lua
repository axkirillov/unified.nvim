local M = {}
local git = require("unified.git")
local global_state = require("unified.state")
local FileTree = require("unified.file_tree.tree")
local render = require("unified.file_tree.render")
local actions = require("unified.file_tree.actions")

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    pattern = "UnifiedBaseCommitUpdated",
    callback = function()
      local commit_hash = global_state.get_commit_base()
      M.show(commit_hash)
    end,
  })
end

function M.create_file_tree_buffer(buffer_path, diff_only, commit_ref_arg)
  local tree_state = require("unified.file_tree.state")
  tree_state.root_path = buffer_path
  tree_state.diff_only = diff_only
  tree_state.commit_ref = commit_ref_arg

  local dir
  local path_exists = vim.fn.filereadable(buffer_path) == 1 or vim.fn.isdirectory(buffer_path) == 1
  if path_exists then
    dir = vim.fn.isdirectory(buffer_path) == 1 and buffer_path or vim.fn.fnamemodify(buffer_path, ":h")
  else
    dir = vim.fn.fnamemodify(buffer_path, ":h")
    if vim.fn.isdirectory(dir) ~= 1 then
      dir = vim.fn.getcwd()
    end
  end

  local is_git_repo = git.is_git_repo(dir)
  local root_dir = dir
  if is_git_repo then
    local git_root_cmd = string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(dir))
    local git_root = vim.trim(vim.fn.system(git_root_cmd))
    if vim.v.shell_error == 0 and git_root ~= "" and vim.fn.isdirectory(git_root .. "/.git") == 1 then
      root_dir = git_root
    else
      local check_dir = dir
      local max_depth = 10
      for _ = 1, max_depth do
        if vim.fn.isdirectory(check_dir .. "/.git") == 1 then
          root_dir = check_dir
          break
        end
        local parent = vim.fn.fnamemodify(check_dir, ":h")
        if parent == check_dir then
          break
        end
        check_dir = parent
      end
    end
  end

  if vim.fn.isdirectory(root_dir) ~= 1 then
    root_dir = vim.fn.getcwd()
  end

  local commit_ref = commit_ref_arg

  local tree = FileTree.new(root_dir)

  local buf = vim.api.nvim_create_buf(false, true)

  local buffer_name = "Unified: File Tree"
  if commit_ref then
    buffer_name = buffer_name .. " (" .. commit_ref .. ")"
  elseif diff_only then
    buffer_name = buffer_name .. " (Diff)"
  end

  pcall(vim.api.nvim_buf_set_name, buf, buffer_name)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "unified_tree"

  render.render_tree(tree, buf)

  tree:update_git_status(root_dir, diff_only, commit_ref, function()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      render.render_tree(tree, buf)

      local win = tree_state.window or global_state.file_tree_win
      if not win then
        return
      end
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      vim.api.nvim_set_current_win(win)
      actions.move_cursor_and_open_file(1)
    end)
  end)

  return buf
end

local function auto_select_and_open_first_file(tree_buf, tree_win)
  local first_file_line = -1
  local first_node = nil
  local line_count = vim.api.nvim_buf_line_count(tree_buf)

  local tree_state = require("unified.file_tree.state")
  for i = 3, line_count - 1 do
    local node = tree_state.line_to_node[i]
    if node and not node.is_dir then
      first_file_line = i
      first_node = node
      break
    end
  end

  if first_node then
    actions.open_file_node(first_node)

    local current_buf_id = vim.api.nvim_win_get_buf(tree_win)
    if not vim.api.nvim_buf_is_valid(current_buf_id) then
      return
    end

    local current_line_count = vim.api.nvim_buf_line_count(current_buf_id)
    local target_line = first_file_line + 1

    if target_line > 0 and target_line <= current_line_count then
      vim.api.nvim_win_set_cursor(tree_win, { target_line, 0 })
    end
  else
  end
end

local function position_cursor_on_first_file(buffer, window)
  if not buffer or not window or not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_win_is_valid(window) then
    return
  end

  local first_file_line = -1
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local tree_state = require("unified.file_tree.state")
  for i = 3, line_count - 1 do
    local node = tree_state.line_to_node[i]
    if node and not node.is_dir then
      first_file_line = i
      break
    end
  end

  if first_file_line > 0 then
    local target_line = first_file_line + 1
    local current_line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
    if target_line <= current_line_count then
      vim.api.nvim_win_set_cursor(window, { target_line, 0 })
    end
  end
end

--- @param commit_hash string The commit hash to compare against.
function M.show(commit_hash)
  local file_path = vim.fn.getcwd()
  local diff_only = true -- Always show diff only for a specific commit

  -- Check if tree window already exists and is valid
  local tree_state = require("unified.file_tree.state")
  if
    tree_state.window
    and vim.api.nvim_win_is_valid(tree_state.window)
    and tree_state.buffer
    and vim.api.nvim_buf_is_valid(tree_state.buffer)
  then
    local new_buf = M.create_file_tree_buffer(file_path, diff_only, commit_hash)

    vim.api.nvim_win_set_buf(tree_state.window, new_buf)
    -- The create function updates tree_state.buffer, but we also need to update global state
    global_state.file_tree_buf = new_buf -- Update global state reference

    -- Focus the tree window
    vim.api.nvim_set_current_win(tree_state.window)

    -- Position cursor on the first file in the updated tree
    position_cursor_on_first_file(new_buf, tree_state.window)

    return true
  end

  -- Tree window doesn't exist, create it
  local tree_buf = M.create_file_tree_buffer(file_path, diff_only, commit_hash)
  if not tree_buf then
    return false
  end -- Exit if buffer creation failed

  -- Create new window for tree
  vim.cmd("topleft 30vsplit") -- Consider making width configurable
  local tree_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  -- Store window reference in tree state and global state
  tree_state.window = tree_win
  global_state.file_tree_win = tree_win
  global_state.file_tree_buf = tree_buf -- Keep global state updated too

  auto_select_and_open_first_file(tree_buf, tree_win)
  return true
end

-- Expose actions for keymaps setup elsewhere if needed (though direct require is preferred)
M.actions = actions

return M
