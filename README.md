# unified.nvim

A Neovim plugin for displaying inline unified diffs directly in your buffer.

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

### File Tree Interaction

When the file tree is open:

-   `j`/`k`: Move the cursor down/up and automatically open the file under the cursor in the main window, displaying its diff.
-   `q`: Close the file tree window.
-   `R`: Refresh the file tree.
-   `?`: Show a help dialog (if implemented).

## Development

### Running Tests

To run the automated tests:

```bash
./test/run_tests.sh
```
## License

MIT
