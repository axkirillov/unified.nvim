#!/bin/bash

# Define test directory and get plugin directory path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"

# Parse command line arguments
USE_SHARED_REPO=1
SPECIFIC_TEST=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --no-shared-repo) USE_SHARED_REPO=0 ;;
    --test=*) SPECIFIC_TEST="${1#*=}" ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# Export environment variables
export UNIFIED_USE_SHARED_REPO=$USE_SHARED_REPO

# Print mode
if [ $USE_SHARED_REPO -eq 1 ]; then
  echo "Running tests with shared Git repository (faster, lower disk I/O)"
else
  echo "Running tests with individual Git repositories (slower, higher reliability)"
fi

# Run all tests or a specific test
if [ -z "$SPECIFIC_TEST" ]; then
  # Run all tests
  echo "Running all tests..."
  "$(dirname "$0")/run_modular_tests.sh" modular
else
  # Run specific test
  echo "Running test: $SPECIFIC_TEST"
  "$(dirname "$0")/run_modular_tests.sh" "$SPECIFIC_TEST"
fi