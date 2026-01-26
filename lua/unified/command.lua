local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Unified", function(opts)
    local state = require("unified.state")

    -- Behave like a toggle when called without args.
    if opts.args == "" and state.is_active() then
      M.reset()
      return
    end

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
  if args == "reset" then
    M.reset()
    return
  end

  local commit_ref = args

  if commit_ref == "" then
    commit_ref = "HEAD"
  end

  local git = require("unified.git")
  local state = require("unified.state")
  local cwd = vim.fn.getcwd()

  git.resolve_commit_hash(commit_ref, cwd, function(hash)
    if not hash then
      vim.api.nvim_echo({ { 'Error: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } }, false, {})
      return
    end

    -- Keep the user-provided ref (e.g. HEAD/main/branch) so it can be re-resolved
    -- later and follow moving refs.
    state.main_win = vim.api.nvim_get_current_win()

    -- Mark Unified active *before* we emit any update events that may open buffers.
    state.set_active(true)
    state.set_commit_base(commit_ref)
  end)

  return nil
end

function M.reset()
  local buffer = vim.api.nvim_get_current_buf()
  local config = require("unified.config")
  local ns_id = config.ns_id
  local hunk_store = require("unified.hunk_store")

  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  hunk_store.clear(buffer)

  local state = require("unified.state")
  if state.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  local windows = vim.api.nvim_list_wins()
  if not state.file_tree_win or not vim.api.nvim_win_is_valid(state.file_tree_win) then
    return
  end

  if #windows == 1 then
    return
  end

  vim.api.nvim_win_close(state.file_tree_win, true)

  state.file_tree_win = nil
  state.file_tree_buf = nil
  state.main_win = nil
  state.set_active(false)
end

return M
