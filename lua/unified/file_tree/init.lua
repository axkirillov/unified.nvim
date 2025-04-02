-- Main entry point for the File Tree module

local git = require("unified.git")
local global_state = require("unified.state") -- Global plugin state
local tree_state_module = require("unified.file_tree.state")
local tree_state = tree_state_module.tree_state
local FileTree = require("unified.file_tree.tree")
local render = require("unified.file_tree.render")
local actions = require("unified.file_tree.actions")

local M = {}

-- Build and render a file tree, returning the buffer handle
function M.create_file_tree_buffer(buffer_path, diff_only, commit_ref_arg)
  -- Store the root path and mode for refresh action
  tree_state.root_path = buffer_path
  tree_state.diff_only = diff_only

  -- Determine the directory to use as the root for scanning/git commands
  local dir
  local path_exists = vim.fn.filereadable(buffer_path) == 1 or vim.fn.isdirectory(buffer_path) == 1
  if path_exists then
    dir = vim.fn.isdirectory(buffer_path) == 1 and buffer_path or vim.fn.fnamemodify(buffer_path, ":h")
  else
    dir = vim.fn.fnamemodify(buffer_path, ":h")
    if vim.fn.isdirectory(dir) ~= 1 then
      dir = vim.fn.getcwd() -- Fallback to CWD
    end
  end

  -- Check if path is in a git repo and find the git root
  local is_git_repo = git.is_git_repo(dir)
  local root_dir = dir
  if is_git_repo then
    local git_root_cmd = string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(dir))
    local git_root = vim.trim(vim.fn.system(git_root_cmd))
    if vim.v.shell_error == 0 and git_root ~= "" and vim.fn.isdirectory(git_root .. "/.git") == 1 then
      root_dir = git_root
    else
      -- Fallback if git root detection fails but is_git_repo was true
      local check_dir = dir
      local max_depth = 10
      for _ = 1, max_depth do
        if vim.fn.isdirectory(check_dir .. "/.git") == 1 then
          root_dir = check_dir
          break
        end
        local parent = vim.fn.fnamemodify(check_dir, ":h")
        if parent == check_dir then break end
        check_dir = parent
      end
    end
  end

  -- Final sanity check for root_dir existence
  if vim.fn.isdirectory(root_dir) ~= 1 then
    root_dir = vim.fn.getcwd()
  end

  -- Determine the commit reference to use
  local commit_ref = commit_ref_arg -- Use argument first

  -- Create file tree instance
  local tree = FileTree.new(root_dir)

  -- Populate the tree based on mode (diff_only or full scan) and git status
  if is_git_repo then
    -- Pass the determined commit_ref to update_git_status
    tree:update_git_status(root_dir, diff_only, commit_ref)
  elseif not diff_only then
    -- Not a git repo, just scan the directory if not in diff_only mode
    tree:scan_directory(root_dir)
  end
  -- If diff_only is true but not a git repo, the tree remains empty (as intended)

  -- Create buffer for file tree
  local buf = vim.api.nvim_create_buf(false, true)

  -- Create a unique buffer name
  local buffer_name = "Unified: File Tree"
  if commit_ref then
    buffer_name = buffer_name .. " (" .. commit_ref .. ")"
  elseif diff_only then
     buffer_name = buffer_name .. " (Diff)"
  end
  -- Try to set the name, ignoring errors
  pcall(vim.api.nvim_buf_set_name, buf, buffer_name)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide" -- Use hide instead of wipe
  vim.bo[buf].filetype = "unified_tree"

  -- Render file tree to buffer (this also updates tree_state)
  render.render_tree(tree, buf)

  -- Set up keymaps for the buffer
  -- Pass options directly to avoid potential issues with shared table
  vim.api.nvim_buf_set_keymap(buf, "n", "j", "j", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "k", "k", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "l", "<Cmd>lua require('unified.file_tree.actions').expand_node()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "h", "<Cmd>lua require('unified.file_tree.actions').collapse_node()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<Cmd>lua require('unified.file_tree.actions').toggle_node()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<C-j>", "<Cmd>lua require('unified.file_tree.actions').toggle_node()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "-", "<Cmd>lua require('unified.file_tree.actions').go_to_parent()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "R", "<Cmd>lua require('unified.file_tree.actions').refresh()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Cmd>lua require('unified.file_tree.actions').close_tree()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "?", "<Cmd>lua require('unified.file_tree.actions').show_help()<CR>", { noremap = true, silent = true })

  return buf
end

-- Show file tree for the current buffer or a specific directory/commit
function M.show_file_tree(path_or_commit, show_all_files)
  local commit_ref = nil
  local file_path = path_or_commit

  -- Determine if the input is likely a commit reference
  if path_or_commit and (path_or_commit == "HEAD" or path_or_commit:match("^HEAD~%d*$") or #path_or_commit == 40 or #path_or_commit == 7) then
     -- Basic check for HEAD, HEAD~N, or commit hash length
     -- A more robust check would involve `git rev-parse --verify` but might be slow here
     commit_ref = path_or_commit
     -- If it's a commit ref, we need a file path to determine the repo root. Use CWD.
     file_path = vim.fn.getcwd()
  elseif not path_or_commit then
     -- Default to current buffer's file or CWD if no path given
     file_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
     if file_path == "" then
        file_path = vim.fn.getcwd()
     end
  end

  -- Check if tree window already exists and is valid
  if
    tree_state.window
    and vim.api.nvim_win_is_valid(tree_state.window)
    and tree_state.buffer
    and vim.api.nvim_buf_is_valid(tree_state.buffer)
  then
    -- Tree is already showing, update its content
    local is_git_repo_update = git.is_git_repo(file_path)
    local diff_only_update = is_git_repo_update and not show_all_files

    -- Create a new buffer with updated content
    -- Pass the determined commit_ref for update
    local new_buf = M.create_file_tree_buffer(file_path, diff_only_update, commit_ref)

    -- Replace the buffer in the existing window
    vim.api.nvim_win_set_buf(tree_state.window, new_buf)
    -- The create function updates tree_state.buffer, but we also need to update global state
    global_state.file_tree_buf = new_buf -- Update global state reference

    -- Focus the tree window
    vim.api.nvim_set_current_win(tree_state.window)
    return true
  end

  -- Tree window doesn't exist, create it
  local is_git_repo_create = git.is_git_repo(file_path)
  -- Default to diff_only mode if in a git repo, unless show_all_files is true
  local diff_only_create = is_git_repo_create and not show_all_files

  -- Create file tree buffer (passing commit_ref if determined)
  local tree_buf = M.create_file_tree_buffer(file_path, diff_only_create, commit_ref)
  if not tree_buf then return false end -- Exit if buffer creation failed

  -- Create new window for tree
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd("topleft 30vsplit") -- Consider making width configurable
  local tree_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  -- Set window options
  vim.api.nvim_win_set_option(tree_win, "number", false)
  vim.api.nvim_win_set_option(tree_win, "relativenumber", false)
  vim.api.nvim_win_set_option(tree_win, "signcolumn", "no")
  vim.api.nvim_win_set_option(tree_win, "cursorline", true)
  vim.api.nvim_win_set_option(tree_win, "winfixwidth", true)
  vim.api.nvim_win_set_option(tree_win, "foldenable", false)
  vim.api.nvim_win_set_option(tree_win, "list", false)
  -- vim.api.nvim_win_set_option(tree_win, "fillchars", "vert:│") -- Optional: for visual vertical line

  -- Store window reference in tree state and global state
  tree_state.window = tree_win
  global_state.file_tree_win = tree_win
  global_state.file_tree_buf = tree_buf -- Keep global state updated too

  -- Return focus to original window
  vim.api.nvim_set_current_win(current_win)

  return true
end

-- Expose actions for keymaps setup elsewhere if needed (though direct require is preferred)
M.actions = actions

return M