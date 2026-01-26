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

  * `j`/`k` or `<Down>`/`<Up>`: Move the cursor down/up between file nodes.
  * `l`: Open the file under the cursor in the main window, displaying its diff.
  * `q`: Close the file tree window.
  * `R`: Refresh the file tree.
  * `?`: Show a help dialog.

When the file tree opens, the first file is automatically opened in the main window.

The file tree displays the Git status of each file:

  - `M`: Modified
  - `A`: Added
  - `D`: Deleted
  - `R`: Renamed
  - `C`: Copied
  - `?`: Untracked

### Navigating Hunks

To navigate between hunks, you'll need to set your own keymaps:

```lua
vim.keymap.set('n', ']h', function() require('unified.navigation').next_hunk() end)
vim.keymap.set('n', '[h', function() require('unified.navigation').previous_hunk() end)
```

### Toggle API

For programmatic control, you can use the toggle function:

```lua
vim.keymap.set('n', '<leader>ud', require('unified').toggle, { desc = 'Toggle unified diff' })
```

This toggles the diff view on/off, remembering the previous commit reference.

### Autocmd hooks

Unified emits `User` autocmds you can use to attach/detach your own buffer-local keymaps.

- `User UnifiedEnter`: Fired when Unified becomes active.
- `User UnifiedExit`: Fired when Unified is deactivated (e.g. toggled off / `:Unified reset`).

Example (install buffer-local hunk-action maps while Unified is active):

```lua
local grp = vim.api.nvim_create_augroup("MyUnifiedMaps", { clear = true })
local touched = {}

vim.api.nvim_create_autocmd("User", {
  pattern = "UnifiedEnter",
  callback = function()
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
      group = grp,
      callback = function(ev)
        if not require("unified.state").is_active() then return end
        if vim.bo[ev.buf].buftype ~= "" then return end
        if touched[ev.buf] then return end
        touched[ev.buf] = true

        local actions = require("unified.hunk_actions")
        vim.keymap.set("n", "gs", actions.stage_hunk, { buffer = ev.buf, desc = "Unified: Stage hunk" })
        vim.keymap.set("n", "gu", actions.unstage_hunk, { buffer = ev.buf, desc = "Unified: Unstage hunk" })
        vim.keymap.set("n", "gr", actions.revert_hunk, { buffer = ev.buf, desc = "Unified: Revert hunk" })
      end,
    })
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "UnifiedExit",
  callback = function()
    vim.api.nvim_clear_autocmds({ group = grp })
    for buf, _ in pairs(touched) do
      pcall(vim.keymap.del, "n", "gs", { buffer = buf })
      pcall(vim.keymap.del, "n", "gu", { buffer = buf })
      pcall(vim.keymap.del, "n", "gr", { buffer = buf })
    end
    touched = {}
  end,
})
```

### Hunk actions (API)

Unified provides a function-only API for hunk actions. Define your own keymaps or commands if desired.

Example keymaps:

```lua
local actions = require('unified.hunk_actions')
vim.keymap.set('n', 'gs', actions.stage_hunk,   { desc = 'Unified: Stage hunk' })
vim.keymap.set('n', 'gu', actions.unstage_hunk, { desc = 'Unified: Unstage hunk' })
vim.keymap.set('n', 'gr', actions.revert_hunk,  { desc = 'Unified: Revert hunk' })
```

Behavior notes:
- Operates on the hunk under the cursor inside a regular file buffer (not in the unified file tree buffer).
- Stage: applies a minimal single-hunk patch to the index.
- Unstage: reverse-applies the hunk patch from the index.
- Revert: reverse-applies the hunk patch to the working tree.
- Binary patches are skipped with a user message.
- After an action, the inline diff and file tree are refreshed automatically.

## Commands

  * `:Unified`: Toggles the diff view. If closed, it shows the diff against `HEAD`. If open, it closes the view.
  * `:Unified <commit_ref>`: Shows the diff against the specified commit reference (e.g., a commit hash, branch name, or tag) and opens the file tree for that range.
  * `:Unified reset`: Removes all unified diff highlights and signs from the current buffer and closes the file tree window if it is open.

## Development

### Running Tests

To run all automated tests:

```bash
make tests
```

To run a specific test function:

```bash
make test TEST=test_file_name.test_function_name
```

## License

MIT
