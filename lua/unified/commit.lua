-- Module for handling commit-related functionality in unified.nvim
local M = {}

-- Dependencies
local state = require("unified.state")

-- Handle the "Unified commit <ref>" command
function M.handle_commit_command(commit_ref)
  if not commit_ref or #commit_ref == 0 then
    vim.api.nvim_echo({ { "Invalid commit format. Use: Unified commit <hash/ref>", "ErrorMsg" } }, false, {})
    return false
  end

  -- Get the unified module
  local unified = require("unified")

  -- Validate commit reference with git
  local cwd = vim.fn.getcwd()
  local file_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

  -- Determine what directory to use for git commands
  local repo_dir = cwd
  if file_path ~= "" then
    -- Use file's directory if we have a file open
    repo_dir = vim.fn.fnamemodify(file_path, ":h")
  end

  -- Check if we're in a git repo
  local repo_check = vim.fn.system(
    string.format("cd %s && git rev-parse --is-inside-work-tree 2>/dev/null", vim.fn.shellescape(repo_dir))
  )

  if vim.trim(repo_check) ~= "true" then
    vim.api.nvim_echo({ { "Not in a git repository", "ErrorMsg" } }, false, {})
    return false
  end

  -- Try to resolve the commit
  local commit_check = vim.fn.system(
    string.format(
      "cd %s && git rev-parse --verify %s 2>/dev/null",
      vim.fn.shellescape(repo_dir),
      vim.fn.shellescape(commit_ref)
    )
  )

  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Invalid git reference: " .. commit_ref, "ErrorMsg" } }, false, {})
    return false
  end

  -- Store a reference to main window if not already active
  if not state.is_active then
    state.main_win = vim.api.nvim_get_current_win()
  end

  -- Store the commit in global state, even if buffer has no name
  local previous_base = state.commit_base
  state.set_commit_base(commit_ref)

  -- Check if buffer has a name before showing diff
  local result = false
  if file_path ~= "" then
    -- Show diff for the commit
    result = unified.show_diff(commit_ref)
  end

  -- Only show file tree if not already active, or if active with a different commit
  -- This preserves the file tree state (cursor position, etc) when just updating the commit ref
  if not state.is_active or previous_base ~= commit_ref then
    -- Show file tree regardless of buffer content
    -- This way we can browse repository even with an empty buffer
    unified.show_file_tree()
  end

  -- Update global state - activate even if we can't show diff in current buffer
  state.is_active = true

  -- Confirm to user
  if file_path == "" then
    vim.api.nvim_echo({ { "Activated file tree with commit base: " .. commit_ref, "Normal" } }, false, {})
  else
    vim.api.nvim_echo({ { "Showing diff against commit: " .. commit_ref, "Normal" } }, false, {})
  end

  return true
end

return M
