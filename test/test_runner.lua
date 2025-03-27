-- Test runner for unified.nvim

-- Initialize unified plugin
require("unified").setup()

-- Load test modules
local test_modules = {
  require('test.test_multiple_lines'),
  -- Add more test modules here as they're split out
}

-- Run all tests
local results = {}
local all_passed = true

for _, test_module in ipairs(test_modules) do
  print("\nRunning tests in module")
  local status, result = pcall(function()
    return test_module.run_tests()
  end)
  
  if not status or not result then
    all_passed = false
    print("Tests FAILED")
    if not status then
      print("Error: " .. tostring(result))
    end
  else
    print("Tests PASSED")
  end
end

-- Exit with proper status code
if all_passed then
  print("\nAll tests PASSED")
  vim.cmd("cq 0")
else
  print("\nSome tests FAILED")
  vim.cmd("cq 1")
end