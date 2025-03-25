# unified.nvim

A Neovim plugin for displaying inline unified diffs directly in your buffer.

## Features

- Show differences between buffer content and git HEAD (default)
- Show differences between buffer content and saved file
- Display added, deleted, and modified lines with distinct highlighting
- Customizable symbols and highlighting
- Simple toggle functionality
- Automatic refresh of diff as you type
- Display added, modified and deleted lines with proper visualization

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'axkirillov/unified.nvim',
  config = function()
    require('unified').setup({
      -- Optional: override default settings
    })
  end
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'axkirillov/unified.nvim',
  config = function()
    require('unified').setup({
      -- Optional: override default settings
    })
  end
}
```

## Configuration

Default configuration:

```lua
require('unified').setup({
  signs = {
    add = "│",
    delete = "│",
    change = "│",
  },
  highlights = {
    add = "DiffAdd",
    delete = "DiffDelete",
    change = "DiffChange",
  },
  line_symbols = {
    add = "+",
    delete = "-",
    change = "~",
  },
  auto_refresh = true, -- Whether to automatically refresh diff when buffer changes
})
```

## Usage

### Commands

- `:Unified` - Show git differences between buffer and git HEAD
- `:Unified toggle` - Toggle the diff display on/off
- `:Unified refresh` - Force refresh of the diff display (useful when auto-refresh is disabled)

### Lua API

```lua
-- Show git differences between buffer and git HEAD
require('unified').show_diff()

-- Show differences between buffer and git HEAD (same as show_diff)
require('unified').show_git_diff()

-- Toggle diff display
require('unified').toggle_diff()

-- Check if diff is currently displayed
require('unified').is_diff_displayed()

-- Set up automatic refresh (happens automatically when show_diff is called)
require('unified').setup_auto_refresh()
```

### Example Key Mappings

```lua
vim.keymap.set('n', '<leader>ud', ':Unified toggle<CR>', { silent = true })
vim.keymap.set('n', '<leader>us', ':Unified<CR>', { silent = true })
vim.keymap.set('n', '<leader>ur', ':Unified refresh<CR>', { silent = true })
```

## Screenshots

[Screenshots will be added here]

## Development

### Running Tests

To run the automated tests:

```bash
./test/run_tests.sh
```

To run a manual test for buffer diff:

```bash
nvim -u NONE -c "set rtp+=." -c "luafile test/manual_test.lua"
```

To run a manual test for git diff:

```bash
nvim -u NONE -c "set rtp+=." -c "luafile test/manual_test_git.lua"
```

## License

MIT
