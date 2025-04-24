# unified.nvim

A Neovim plugin for displaying inline unified diffs directly in your buffer.

## Usage

The primary command is `:Unified`. Its behavior depends on whether arguments are provided and the current state of the diff view:

*   `:Unified <commit_ref>`: Shows a diff view comparing the current buffer(s) against the specified `<commit_ref>`. It also opens a file tree showing files changed in that commit range. Autocompletion for `<commit_ref>` is available.
*   `:Unified` with no arguments shows the diff against `HEAD` (equivalent to `:Unified HEAD`).

Opening any file from the file tree will display its specific diff.
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

- `:Unified <commit_ref>`: Shows the diff against the specified commit reference and opens the file tree for that range.
- `:Unified`: Toggles the view. If closed, shows diff against `HEAD`. If open, closes the view.

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
