# unified.nvim

A Neovim plugin for displaying inline unified diffs directly in your buffer.

## Features

- Show differences between buffer content and git HEAD (default)
- Show differences between buffer content and saved file
- Display added, deleted, and modified lines with distinct highlighting
- Customizable symbols and highlighting
- Simple toggle functionality
- changed this line
- deleted this line

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
  default_diff_mode = "git", -- Options: "git", "buffer"
})
```

## Usage

### Commands

- `:UnifiedDiffToggle` - Toggle the diff display on/off
- `:UnifiedDiffShow` - Show differences based on default configuration
- `:UnifiedDiffGit` - Show differences between buffer and git HEAD
- `:UnifiedDiffBuffer` - Show differences between buffer and saved file

### Lua API

```lua
-- Show differences based on configured default mode
require('unified').show_diff()

-- Show differences between buffer and git HEAD
require('unified').show_git_diff()

-- Show differences between buffer and saved file
require('unified').show_buffer_diff()

-- Toggle diff display
require('unified').toggle_diff()
```

### Example Key Mappings

```lua
vim.keymap.set('n', '<leader>ud', ':UnifiedDiffToggle<CR>', { silent = true })
vim.keymap.set('n', '<leader>us', ':UnifiedDiffShow<CR>', { silent = true })
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
