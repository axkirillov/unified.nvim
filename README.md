# unified.nvim

A Neovim plugin for displaying inline unified diffs directly in your buffer.

## Usage

Calling `Unified <commit>` opens a file tree, showing files that changed since the specified commit.
Opening any of the files in the tree will show a unified diff for that file.

## Installation

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
})
```

## Usage

### Commands

- `:Unified` - Show git differences between buffer and git HEAD
- `:Unified <commit>` - Show git diff between index and commit

### Lua API

```lua
```

## Development

### Running Tests

To run the automated tests:

```bash
./test/run_tests.sh
```
## License

MIT
