# unified.nvim Tests

This directory contains tests for the unified.nvim plugin.

## Running Tests

There are multiple ways to run the tests:

```bash
# Run all tests (using shared Git repository by default)
./run_tests.sh

# Run all tests with individual Git repositories
./run_tests.sh --no-shared-repo

# Run a specific test
./run_tests.sh --test=test_multiple_lines.test_multiple_added_lines

# Or use the more detailed runner directly:
./run_modular_tests.sh
```

The modular test runner offers additional options:

```bash
# Run all tests (same as no arguments)
./run_modular_tests.sh all

# Run a specific test by module and function name
./run_modular_tests.sh test_multiple_lines.test_multiple_added_lines
```

### Performance Optimization

The tests now support a shared Git repository mode (enabled by default) which significantly reduces disk I/O and improves test performance by:

1. Creating a single Git repository once for all tests
2. Using Git branches and resets instead of file system operations
3. Isolating each test in its own branch

To use individual repositories (old behavior), run with the `--no-shared-repo` flag.

## Test Structure

The tests are organized as follows:

- `test_utils.lua` - Common utilities for all tests
- `test_basic.lua` - Basic functionality tests
- `test_rendering.lua` - Tests for UI rendering features
- `test_features.lua` - Tests for plugin features like auto-refresh and commit diffing
- `test_multiple_lines.lua` - Tests for the multiple line highlight bug fix
- `test_runner.lua` - Modular test runner

## Creating New Tests

To add a new test, add a function to an appropriate module file or create a new module file. Test functions should follow these guidelines:

1. Name the function with the `test_` prefix
2. Return `true` on success
3. Use `assert()` for test conditions
4. Clean up resources after the test

Example:

```lua
function M.test_my_new_feature()
  -- Setup
  local repo = utils.create_git_repo()
  if not repo then
    return true
  end
  
  -- Test code...
  
  -- Assertions
  assert(some_condition, "Error message")
  
  -- Cleanup
  utils.cleanup_git_repo(repo)
  
  return true
end
```