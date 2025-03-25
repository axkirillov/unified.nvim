-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
	return
end
vim.g.loaded_unified_nvim = true

-- Create user commands
vim.api.nvim_create_user_command('UnifiedDiffToggle', function()
	require('unified').toggle_diff()
end, {})

vim.api.nvim_create_user_command('UnifiedDiffShow', function()
	require('unified').show_diff()
end, {})

-- Buffer diff command removed

vim.api.nvim_create_user_command('UnifiedDiffGit', function()
	require('unified').show_git_diff()
end, {})

-- Initialize the plugin with default settings
require('unified').setup()

