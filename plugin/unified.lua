-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
  return
end
vim.g.loaded_unified_nvim = true

-- Create a single unified command with optional toggle argument
vim.api.nvim_create_user_command("Unified", function(opts)
  if opts.args == "toggle" then
    require("unified").toggle_diff()
  elseif opts.args == "refresh" then
    -- Force refresh if diff is displayed
    local unified = require("unified")
    if unified.is_diff_displayed() then
      unified.show_diff()
    else
      vim.api.nvim_echo({ { "No diff currently displayed", "WarningMsg" } }, false, {})
    end
  else
    require("unified").show_diff()
  end
end, {
  nargs = "?",
  complete = function(_, _, _)
    return { "toggle", "refresh" }
  end,
})

-- Initialize the plugin with default settings
require("unified").setup()
