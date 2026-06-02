#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

on_err() {
  local exit_code=$?
  echo "Error: ${BASH_SOURCE[1]-$0}:${BASH_LINENO[0]-?} exit ${exit_code}" >&2
  exit "$exit_code"
}
trap on_err ERR

on_exit() { :; }
trap on_exit EXIT

# Define test directory and get plugin directory path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"

# Preflight: ensure Neovim is available
if ! command -v nvim >/dev/null 2>&1; then
  echo "Error: Neovim (nvim) not found in PATH" >&2
  exit 127
fi

# The suite spins up throwaway git repos in tempdirs and runs `git` inside them. When
# the suite is launched from within a git operation -- notably this project's
# pre-commit hook -- git exports GIT_DIR, GIT_INDEX_FILE and friends, and those `git`
# calls would inherit them and operate on *this* repo instead of the temp one, failing
# every history-dependent test. Scrub them so each temp repo is discovered from its own
# working directory. (Unsetting an already-unset var is a no-op, safe under `set -u`.)
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_REFLOG_ACTION

# Run modular tests
if [ -n "$1" ]; then
  # Handle special arguments
  if [ "$1" = "modular" ] || [ "$1" = "all" ]; then
    echo "Running all tests..."
    UNIFIED_PLUGIN_DIR="$PLUGIN_DIR" nvim --headless -u "$SCRIPT_DIR/minimal_init.lua" +"lua local ok=require('test.test_runner').run_all_tests(); if ok then vim.cmd('qa!') else vim.cmd('cq!') end"
  else
    echo "Running specific test: $1"
    SPECIFIC_TEST="$1" UNIFIED_PLUGIN_DIR="$PLUGIN_DIR" nvim --headless -u "$SCRIPT_DIR/minimal_init.lua" +"lua local ok,err=pcall(function() require('test.test_runner').run_test(vim.env.SPECIFIC_TEST) end); if ok then vim.cmd('qa!') else print(err) vim.cmd('cq!') end"
  fi
else
  # No arguments passed, run all tests
  echo "Running all tests..."
  UNIFIED_PLUGIN_DIR="$PLUGIN_DIR" nvim --headless -u "$SCRIPT_DIR/minimal_init.lua" +"lua local ok=require('test.test_runner').run_all_tests(); if ok then vim.cmd('qa!') else vim.cmd('cq!') end"
fi