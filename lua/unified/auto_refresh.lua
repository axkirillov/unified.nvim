local M = {}

local default = {
  debounce_delay = 300,
  augroup_name = "UnifiedDiffAutoRefresh",
}

-- Create (once) the augroup used for all auto-refresh autocmds and remember its
-- id in global state so `:Unified reset` can tear it down. We deliberately use
-- clear=false: each opened buffer registers its own autocmd, and recreating the
-- group with clear=true (as before) would wipe the autocmds of every previously
-- opened buffer, so only the most recently opened file would auto-refresh.
local function ensure_augroup()
  local state = require("unified.state")
  if not state.auto_refresh_augroup then
    state.auto_refresh_augroup = vim.api.nvim_create_augroup(default.augroup_name, { clear = false })
  end
  return state.auto_refresh_augroup
end

---@param buffer number
function M.setup(buffer)
  -- Respect the user's configuration: when auto-refresh is disabled, do nothing.
  local config = require("unified.config")
  if not config.values.auto_refresh then
    return
  end

  local diff = require("unified.diff")
  local async = require("unified.utils.async")
  local group = ensure_augroup()

  -- Remove any prior autocmds for *this* buffer to avoid duplicates, while
  -- leaving other buffers' refresh autocmds intact.
  pcall(vim.api.nvim_clear_autocmds, { group = group, buffer = buffer })

  local debounced_show_diff = async.debounce(function()
    local state = require("unified.state")
    local ok, commit = pcall(state.get_commit_base)
    if not ok then
      return
    end

    -- Run inside a coroutine so the git calls in show_git_diff_against_commit
    -- execute asynchronously and never block the UI while typing.
    async.run(function()
      require("unified.git").show_git_diff_against_commit(commit, buffer)
    end)
  end, default.debounce_delay)

  vim.api.nvim_create_autocmd({
    "TextChanged",
    "InsertLeave",
    "FileChangedShell",
  }, {
    group = group,
    buffer = buffer,
    callback = function()
      if diff.is_diff_displayed(buffer) then
        debounced_show_diff()
      end
    end,
  })
end

return M
