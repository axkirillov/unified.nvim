-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
  return
end
vim.g.loaded_unified_nvim = true

-- Create a single unified command with optional toggle argument
vim.api.nvim_create_user_command("Unified", function(opts)
  if opts.args == "toggle" then
    require("unified").toggle_diff()
  else
    require("unified").show_diff()
  end
end, {
  nargs = "?",
  complete = function(_, _, _)
    return { "toggle" }
  end,
})

-- Initialize the plugin with default settings
require("unified").setup()
