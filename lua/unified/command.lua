local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Unified", function(opts)
    M.run(opts.args)
  end, {
    nargs = "*",
    complete = function(ArgLead, CmdLine, _)
      if CmdLine:match("^Unified%s+") then
        local suggestions = { "HEAD", "HEAD~1", "main", "reset" }
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
end

M.run = function(args)
  local unified = require("unified")
  if args == "reset" then
    unified.deactivate()
    return
  end

  local commit_ref = args

  if commit_ref == "" then
    commit_ref = "HEAD"
  end

  local commit_hash = require("unified.git").resolve_commit_hash(commit_ref)

  local state = require("unified.state")
  if not state.is_active then
    state.main_win = vim.api.nvim_get_current_win()
  end

  state.set_commit_base(commit_hash)

  local tree = require("unified.file_tree")
  tree.show_file_tree(commit_hash)

  state.is_active = true

  return true
end

return M
