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

  if args == "" then
    args = "HEAD"
  end

  unified.handle_commit_command(args)
end

return M
