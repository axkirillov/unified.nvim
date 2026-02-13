local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Unified", function(opts)
    M.run(opts.args)
  end, {
    nargs = "*",
    complete = function(ArgLead, CmdLine, _)
      if CmdLine:match("^Unified%s+") then
        local suggestions = { "-s", "HEAD", "HEAD~1", "main", "reset" }
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
  -- Handle reset command
  if args == "reset" then
    M.reset()
    return
  end

  -- Parse arguments to check for "-s" flag (snacks backend)
  local args_parts = vim.split(args, "%s+", { trimempty = true })
  local use_snacks = args_parts[1] == "-s"
  local commit_ref
  
  if use_snacks then
    -- If using snacks, the commit ref is the second argument (required)
    commit_ref = args_parts[2]
    if not commit_ref then
      vim.api.nvim_echo({ { 'Error: -s requires a git ref argument (e.g., ":Unified -s HEAD")', "ErrorMsg" } }, false, {})
      return
    end
  else
    -- Default backend: use the entire args string as commit ref (or HEAD if empty)
    commit_ref = args ~= "" and args or "HEAD"
  end

  local git = require("unified.git")
  local state = require("unified.state")
  local cwd = vim.fn.getcwd()

  if use_snacks then
    -- Use Snacks backend
    git.resolve_commit_hash(commit_ref, cwd, function(hash)
      if not hash then
        vim.api.nvim_echo({ { 'Error: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } }, false, {})
        return
      end

      -- Keep the user-provided ref so it can be re-resolved later
      state.set_backend("snacks")
      state.set_active(true)
      state.main_win = vim.api.nvim_get_current_win()
      
      -- This triggers the autocmd which calls snacks_backend.show
      state.set_commit_base(commit_ref)
    end)
  else
    -- Use default backend
    git.resolve_commit_hash(commit_ref, cwd, function(hash)
      if not hash then
        vim.api.nvim_echo({ { 'Error: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } }, false, {})
        return
      end

      -- Keep the user-provided ref so it can be re-resolved later
      state.set_backend("default")
      state.set_active(true)
      state.main_win = vim.api.nvim_get_current_win()

      -- This triggers the autocmd which calls file_tree.show
      state.set_commit_base(commit_ref)
    end)
  end

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
  state.set_backend("default")
end

return M
