# unified.nvim Development Guide

## Commands

### Testing
- Run all tests: `nvim --headless -c "lua require('test.test_unified').run_tests()" -c "qa!"`
- Run single test: `nvim --headless -c "lua require('test.test_unified').test_NAME({})" -c "qa!"` (replace NAME with test name)
- Manual test: `nvim -u NONE -c "set rtp+=." -c "luafile test/manual_test_git.lua"`

### Linting
- No specific linter configured. Use stylua for formatting.

## Code Style Guidelines

### Formatting
- Use tabs for indentation (not spaces)
- Max line length: ~120 characters
- Single quotes for strings when possible

### Naming Conventions
- Functions: `snake_case`
- Variables: `snake_case`
- Module: `M` for the main module table

### Architecture
- Public API exposed via the `M` table
- Configuration through `M.setup()` function
- Use Neovim's namespace and extmark system for highlights
- Use sign column for line indicators

### Error Handling
- Use `vim.api.nvim_echo()` for user notifications
- Graceful fallback for non-Git files
- Return `true`/`false` from functions to indicate success/failure