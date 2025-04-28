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

## Requirements

- Neovim >= 0.5.0
- Git
- A [Nerd Font](https://www.nerdfonts.com/) installed and configured in your terminal/GUI is required to display file icons correctly in the file tree.

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

#### Status Indicators

The file tree displays the Git status of each file:

-   `M`: Modified
-   `A`: Added
-   `D`: Deleted
-   `R`: Renamed
-   `C`: Copied
-   `?`: Untracked

#### Path Shortening

To fit longer paths within the file tree window, paths are automatically shortened. The beginning part of the path might be replaced with `...` if it exceeds the available width, prioritizing the display of the filename and its immediate parent directories.

#### Keymaps

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
