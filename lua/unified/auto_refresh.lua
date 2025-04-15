local M = {}

local default = {
  debouce_delay = 300,
  augroup_name = "UnifiedDiffAutoRefresh",
}

---@param show_diff function
function M.setup(show_diff)
  local diff = require("unified.diff")
  local async = require("unified.utils.async")
  local group_name = default.augroup_name
  local debounce_delay = default.debouce_delay
  local buffer = vim.api.nvim_get_current_buf()

  vim.api.nvim_create_augroup(group_name, { clear = true })

  local debounced_show_diff = async.debounce(function()
    show_diff()
  end, debounce_delay)

  vim.api.nvim_create_autocmd({
    "TextChanged",
    "InsertLeave",
    "FileChangedShell",
  }, {
    group = group_name,
    callback = function()
      if diff.is_diff_displayed(buffer) then
        debounced_show_diff()
      end
    end,
  })
end

return M
