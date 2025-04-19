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
  complete = function(ArgLead, CmdLine, _)
    if CmdLine:match("^Unified%s+") then
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
