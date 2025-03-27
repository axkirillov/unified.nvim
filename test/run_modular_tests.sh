#!/bin/bash

# Define test directory and get plugin directory path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"

# Run modular tests
if [ -n "$1" ]; then
  # Handle special arguments
  if [ "$1" == "modular" ] || [ "$1" == "all" ]; then
    echo "Running all tests..."
    TMP_SCRIPT=$(mktemp)
    echo "local runner = require('test.test_runner')
local success = runner.run_all_tests()
if success then
  print('All tests passed!')
  os.exit(0)
else
  print('Some tests failed!')
  os.exit(1)
end" > $TMP_SCRIPT
    
    nvim --headless \
      -c "set rtp+=$PLUGIN_DIR" \
      -c "luafile $TMP_SCRIPT" \
      -c "qa! 1"
    
    EXIT_CODE=$?
    rm $TMP_SCRIPT
    exit $EXIT_CODE
  else
    echo "Running specific test: $1"
    # Parse module and test name from dot notation
    MODULE_NAME=$(echo $1 | awk -F. '{print $1}')
    TEST_NAME=$(echo $1 | awk -F. '{print $NF}')
    
    # Set up environment and run test in a new Neovim instance
    TMP_SCRIPT=$(mktemp)
    echo "local M = require('test.$MODULE_NAME')
if M.$TEST_NAME then
  local success, result = pcall(M.$TEST_NAME)
  if success and result then
    print('Test $TEST_NAME passed!')
    os.exit(0)
  else
    print('Test $TEST_NAME failed: ' .. tostring(result))
    os.exit(1) 
  end
else
  print('Test $TEST_NAME not found in module $MODULE_NAME')
  os.exit(1)
end" > $TMP_SCRIPT
    
    nvim --headless \
      -c "set rtp+=$PLUGIN_DIR" \
      -c "luafile $TMP_SCRIPT" \
      -c "qa! 1"  # Fallback exit code if the script doesn't explicitly exit
    
    EXIT_CODE=$?
    rm $TMP_SCRIPT
    exit $EXIT_CODE
  fi
else
  # No arguments passed, run all tests
  echo "Running all tests..."
  
  TMP_SCRIPT=$(mktemp)
  echo "local runner = require('test.test_runner')
local success = runner.run_all_tests()
if success then
  print('All tests passed!')
  os.exit(0)
else
  print('Some tests failed!')
  os.exit(1)
end" > $TMP_SCRIPT
  
  nvim --headless \
    -c "set rtp+=$PLUGIN_DIR" \
    -c "luafile $TMP_SCRIPT" \
    -c "qa! 1"
  
  EXIT_CODE=$?
  rm $TMP_SCRIPT
  
  if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\nAll tests passed!"
    exit 0
  else
    echo -e "\nSome tests failed!"
    exit 1
  fi
fi