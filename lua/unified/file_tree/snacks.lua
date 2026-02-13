local M = {}
local global_state = require("unified.state")
local tree_state = require("unified.file_tree.state")
local git = require("unified.git")

--- Shows the file tree using Snacks git_diff picker
--- @param commit_hash string|nil The commit hash to compare against
function M.show(commit_hash)
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify(
      "Snacks.nvim is not installed. Please install folke/snacks.nvim or set file_tree.backend = 'default'",
      vim.log.levels.ERROR
    )
    return false
  end

  local file_path = vim.fn.getcwd()
  local root_dir = file_path

  -- Find git root
  local is_git_repo = git.is_git_repo(file_path)
  if is_git_repo then
    local git_root_cmd =
      string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(file_path))
    local git_root = vim.trim(vim.fn.system(git_root_cmd))
    if vim.v.shell_error == 0 and git_root ~= "" and vim.fn.isdirectory(git_root .. "/.git") == 1 then
      root_dir = git_root
    end
  end

  if not is_git_repo then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return false
  end

  -- Store commit reference
  tree_state.commit_ref = commit_hash
  tree_state.root_path = root_dir
  tree_state.diff_only = true

  -- Use Snacks git_diff picker with the specified base commit
  local picker_opts = {
    source = "git_diff",
    base = commit_hash or "HEAD",
    cwd = root_dir,
    group = true, -- Group changes by file (not individual hunks)
    -- Custom confirm action to show unified diff when file is selected
    confirm = function(picker, item)
      if not item or not item.file then
        return
      end

      -- Get or create the main window
      local main_win = global_state.get_main_window()
      if not main_win or not vim.api.nvim_win_is_valid(main_win) then
        vim.cmd("rightbelow vsplit")
        main_win = vim.api.nvim_get_current_win()
        global_state.main_win = main_win
      end

      -- Open the file in the main window
      vim.api.nvim_set_current_win(main_win)
      vim.cmd("edit " .. vim.fn.fnameescape(item.file))

      -- Show the unified diff for the current buffer
      local diff = require("unified.diff")
      diff.show_current(commit_hash)

      -- Setup auto-refresh
      local auto_refresh = require("unified.auto_refresh")
      auto_refresh.setup(vim.api.nvim_get_current_buf())

      -- Return focus to the picker
      if picker and picker.layout and picker.layout.win and picker.layout.win.win then
        if vim.api.nvim_win_is_valid(picker.layout.win.win) then
          vim.api.nvim_set_current_win(picker.layout.win.win)
        end
      end
    end,
  }

  -- Open the git_diff picker
  local picker = snacks.picker(picker_opts)

  if picker and picker.layout and picker.layout.win then
    tree_state.window = picker.layout.win.win
    global_state.file_tree_win = picker.layout.win.win
  end

  return true
end

--- Close the Snacks file tree
function M.close()
  if tree_state.window and vim.api.nvim_win_is_valid(tree_state.window) then
    vim.api.nvim_win_close(tree_state.window, true)
  end
  tree_state.window = nil
  global_state.file_tree_win = nil
end

return M
