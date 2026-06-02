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
      vim.api.nvim_echo(
        { { 'Error: -s requires a git ref argument (e.g., ":Unified -s HEAD")', "ErrorMsg" } },
        false,
        {}
      )
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

      -- The inline diff always follows the buffer you are in. The file tree is a
      -- side panel for navigation only; it no longer drives which file is diffed.
      -- Show the current buffer's diff now, while it is still focused (set_commit_base
      -- below may move the cursor into the tree when file_tree.focus is set).
      local cur_win = vim.api.nvim_get_current_win()
      local cur_buf = vim.api.nvim_get_current_buf()
      require("unified.diff").show_current(commit_ref)
      require("unified.auto_refresh").setup(cur_buf)

      -- The blocking diff above has populated the hunk store, so land the cursor
      -- on the first hunk now, before set_commit_base may move focus to the tree.
      if require("unified.config").values.jump_to_first_hunk then
        require("unified.navigation").jump_to_first_hunk(cur_win, cur_buf)
      end

      -- This triggers the autocmd which calls file_tree.show
      state.set_commit_base(commit_ref)
    end)
  end

  return nil
end

function M.reset()
  local config = require("unified.config")
  local ns_id = config.ns_id
  local hunk_store = require("unified.hunk_store")

  -- Clear highlights, signs and hunk data from ALL buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      vim.fn.sign_unplace("unified_diff", { buffer = buf })
      hunk_store.clear(buf)
    end
  end

  local state = require("unified.state")
  if state.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  -- Close the tree window if one is still open. This window close is
  -- conditional, but the state teardown below is NOT: the tree may already have
  -- been closed (e.g. via `q`) while the inline diff is still active. Previously
  -- the early returns here skipped set_active(false), leaving the plugin stuck
  -- "active" so toggle() could never turn the diff back on.
  local windows = vim.api.nvim_list_wins()
  if state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win) and #windows > 1 then
    vim.api.nvim_win_close(state.file_tree_win, true)
  end
  -- Always drop the tree references, even if the window was already gone (closed
  -- via `q`) or we kept it as the last window. A dangling handle would make the
  -- next :Unified think a tree still exists and try to reuse it.
  state.file_tree_win = nil
  state.file_tree_buf = nil

  state.main_win = nil
  state.set_active(false)
  state.set_backend("default")
end

return M
