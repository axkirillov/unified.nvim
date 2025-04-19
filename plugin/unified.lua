-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
  return
end
vim.g.loaded_unified_nvim = true

-- Create a single unified command with optional arguments
vim.api.nvim_create_user_command("Unified", function(opts)
  local args = opts.args

  local unified = require("unified")
  local state = require("unified.state")

  if args == "" then
    -- No arguments: Check state
    if state.is_active then
      -- If active, deactivate (close the view)
      unified.deactivate()
    else
      -- If inactive, show diff against HEAD
      unified.handle_commit_command("HEAD")
    end
  else
    -- Arguments provided: Treat as commit reference
    unified.handle_commit_command(args)
  end
end, {
  nargs = "*",
  complete = function(ArgLead, CmdLine, _) -- Use ArgLead and CmdLine
    -- Basic command completion
    -- Check if we are completing the argument for Unified
    if CmdLine:match("^Unified%s+") then
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

      -- Provide some common references
      local suggestions = { "HEAD", "HEAD~1", "HEAD~2", "main", "master" }
      local filtered_suggestions = {}
      for _, suggestion in ipairs(suggestions) do
        if suggestion:sub(1, #ArgLead) == ArgLead then
          table.insert(filtered_suggestions, suggestion)
        end
      end
      return filtered_suggestions
    end
    return {}
  end,
})

-- Initialize the plugin with default settings
require("unified").setup()
