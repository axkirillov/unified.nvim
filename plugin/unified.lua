-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
  return
end
vim.g.loaded_unified_nvim = true

-- Create a single unified command with optional arguments
vim.api.nvim_create_user_command("Unified", function(opts)
  local args = opts.args

  if args == "" then
    require("unified").toggle_diff()
  elseif args == "toggle" then
    require("unified").toggle_diff()
  elseif args == "refresh" then
    -- Force refresh if diff is displayed
    local unified = require("unified")
    local state = require("unified.state")
    if state.is_active then
      unified.show_diff()
    else
      vim.api.nvim_echo({ { "No diff currently displayed", "WarningMsg" } }, false, {})
    end
  elseif args == "tree" then
    -- Just show the file tree with diff-only mode (only files with changes)
    require("unified").show_file_tree(nil, false)
  elseif args == "debug" then
    -- Toggle debug mode
    vim.g.unified_debug = not vim.g.unified_debug
    vim.api.nvim_echo({ { "Debug mode " .. (vim.g.unified_debug and "enabled" or "disabled"), "Normal" } }, false, {})
  elseif args:match("^commit%s+") then
    -- Extract commit hash from the command
    local commit = args:match("^commit%s+(.+)$")
    -- Use the dedicated commit module to handle this command
    require("unified.commit").handle_commit_command(commit)
  else
    local unified = require("unified")
    local state = require("unified.state")

    -- If already active, deactivate first to reset state
    if state.is_active then
      unified.deactivate()
    end

    -- Activate the diff display
    unified.activate()
  end
end, {
  nargs = "*",
  complete = function(_, line, _)
    -- Basic command completion
    if line:match("^Unified%s+$") then
      return { "toggle", "refresh", "tree", "commit", "debug" }
    elseif line:match("^Unified%s+commit%s+") then
      -- Try to get recent commits for completion
      local buffer = vim.api.nvim_get_current_buf()
      local file_path = vim.api.nvim_buf_get_name(buffer)
      local repo_dir

      if file_path == "" then
        -- Use current directory for empty buffers
        repo_dir = vim.fn.getcwd()
      else
        -- Use file's directory
        repo_dir = vim.fn.fnamemodify(file_path, ":h")
      end

      -- Check if we're in a git repo
      local repo_check = vim.fn.system(
        string.format("cd %s && git rev-parse --is-inside-work-tree 2>/dev/null", vim.fn.shellescape(repo_dir))
      )

      if vim.trim(repo_check) ~= "true" then
        return {}
      end

      -- Provide some common references
      return { "HEAD", "HEAD~1", "HEAD~2", "main", "master" }
    end
    return {}
  end,
})

-- Initialize the plugin with default settings
require("unified").setup()
