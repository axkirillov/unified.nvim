#!/bin/bash

# Define test directory and get plugin directory path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"

# Create temp file to capture test results
RESULTS_FILE=$(mktemp)

echo "Running tests for unified.nvim..."
echo "Plugin directory: $PLUGIN_DIR"
echo "Results will be written to: $RESULTS_FILE"

# Run Neovim with minimal config, loading the plugin and running tests
nvim --headless \
  -u NONE \
  -c "set rtp+=$PLUGIN_DIR" \
  -c "source $PLUGIN_DIR/plugin/unified.lua" \
  -c "luafile $PLUGIN_DIR/test/test_unified.lua" \
  -c "lua vim.g.test_results = _G.test_unified.run_tests()" \
  -c "lua if vim.g.test_results then vim.fn.writefile({'success'}, '$RESULTS_FILE') else vim.fn.writefile({'failure'}, '$RESULTS_FILE') end" \
  -c "qa!"

# Check if test succeeded
if [ "$(cat "$RESULTS_FILE")" = "success" ]; then
  echo "Tests PASSED!"
  exit 0
else
  echo "Tests FAILED!"
  exit 1
fi