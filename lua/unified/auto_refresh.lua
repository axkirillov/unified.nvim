local M = {}

local default = {
  debouce_delay = 300,
  augroup_name = "UnifiedDiffAutoRefresh",
}

---@param buffer number
function M.setup(buffer)
  local diff = require("unified.diff")
  local async = require("unified.utils.async")
  local group_name = default.augroup_name
  local debounce_delay = default.debouce_delay

  vim.api.nvim_create_augroup(group_name, { clear = true })

  local debounced_show_diff = async.debounce(function()
    local state = require("unified.state")
    local commit = state.get_commit_base()

    local git = require("unified.git")
    git.show_git_diff_against_commit(commit, buffer)
  end, debounce_delay)

  vim.api.nvim_create_autocmd({
    "TextChanged",
    "InsertLeave",
    "FileChangedShell",
  }, {
    group = group_name,
    buffer = buffer,
    callback = function()
      if diff.is_diff_displayed(buffer) then
        debounced_show_diff()
      end
    end,
  })
end

return M
