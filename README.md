<a href="https://dotfyle.com/plugins/axkirillov/unified.nvim">
	<img src="https://dotfyle.com/plugins/axkirillov/unified.nvim/shield?style=flat" />
</a>

# unified.nvim

A Neovim plugin for displaying inline unified diffs directly in your buffer.

<img width="1840" alt="image" src="https://github.com/user-attachments/assets/7655659e-c8af-40c5-ad70-59f67a2b16d9" />

## Features

* **Inline Diffs**: View git diffs directly in your buffer, without needing a separate window.
* **File Tree Explorer**: A file tree explorer is displayed, showing all files that have been changed.
* **Git Gutter Signs**: Gutter signs are used to indicate added, modified, and deleted lines.
* **Customizable**: Configure the signs, highlights, and line symbols to your liking.
* **Auto-refresh**: The diff view automatically refreshes as you make changes to the buffer.

## Requirements

-   Neovim >= 0.5.0
-   Git
-   A [Nerd Font](https://www.nerdfonts.com/) installed and configured in your terminal/GUI is required to display file icons correctly in the file tree.

## Installation

You can install `unified.nvim` using your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'axkirillov/unified.nvim',
  opts = {
    -- your configuration comes here
  }
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'axkirillov/unified.nvim',
  config = function()
    require('unified').setup({
      -- your configuration comes here
    })
  end
}
```

## Configuration

You can configure `unified.nvim` by passing a table to the `setup()` function. Here are the default settings:

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

1.  Open a file in a git repository.
2.  Make some changes to the file.
3.  Run the command `:Unified` to display the diff against `HEAD` and open the file tree.
4.  To close the diff view and file tree, run `:Unified` again.
5.  To show the diff against a specific commit, run `:Unified <commit_ref>`, for example `:Unified HEAD~1`.

### File Tree Interaction

When the file tree is open, you can use the following keymaps:

  * `j`/`k`: Move the cursor down/up. The file under the cursor will be opened in the main window, displaying its diff.
  * `q`: Close the file tree window.
  * `R`: Refresh the file tree.
  * `?`: Show a help dialog.

The file tree displays the Git status of each file:

  - `M`: Modified
  - `A`: Added
  - `D`: Deleted
  - `R`: Renamed
  - `C`: Copied
  - `?`: Untracked

## Commands

  * `:Unified`: Toggles the diff view. If closed, it shows the diff against `HEAD`. If open, it closes the view.
  * `:Unified <commit_ref>`: Shows the diff against the specified commit reference (e.g., a commit hash, branch name, or tag) and opens the file tree for that range.
  * `:Unified reset`: Removes all unified diff highlights and signs from the current buffer and closes the file tree window if it is open.

## Development

### Running Tests

To run the automated tests:

```bash
./test/run_tests.sh
```

## License

MIT
