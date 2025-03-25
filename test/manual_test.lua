-- Manual test for unified.nvim
-- Run with: nvim -u NONE -c "set rtp+=." -c "luafile test/manual_test.lua"

-- Initialize plugin
require('unified').setup()

-- Source the plugin file to register commands
vim.cmd('source plugin/unified.lua')

-- Create a test file with initial content
local test_file = vim.fn.tempname()
vim.fn.writefile({
  'This is line 1',
  'This is line 2',
  'This is line 3',
  'This is line 4',
  'This is line 5'
}, test_file)

-- Open the file
vim.cmd('edit ' .. test_file)

-- Make some modifications to demonstrate diff
vim.api.nvim_buf_set_lines(0, 0, 1, false, {'This is modified line 1'})  -- Change line 1
vim.api.nvim_buf_set_lines(0, 2, 3, false, {})                        -- Delete line 3
vim.api.nvim_buf_set_lines(0, 3, 3, false, {'This is a new line'})    -- Add new line

-- Print instructions
print('Manual Test Instructions:')
print('1. The file has been modified but not saved')
print('2. Run :UnifiedDiffShow to display the diff')
print('3. Run :UnifiedDiffToggle to toggle the diff display')
print('4. When done, exit with :q!')
print('')
print('Test file: ' .. test_file)