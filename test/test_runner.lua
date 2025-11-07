-- Test runner for unified.nvim
local M = {}

-- Load test modules
local test_utils = require("test.test_utils")
local test_basic = require("test.test_basic")
local test_rendering = require("test.test_rendering")
local test_features = require("test.test_features")
local test_multiple_lines = require("test.test_multiple_lines")
local test_file_tree = require("test.test_file_tree")
local test_hunk_management = require("test.test_hunk_management")
local test_hunk_actions = require("test.test_hunk_actions")
-- Helper to run a group of tests
local function run_test_group(group, group_name)
  local function is_test_function(name)
    return type(group[name]) == "function" and name:match("^test_")
  end

  local function get_tests()
    local tests = {}
    for name, _ in pairs(group) do
      if is_test_function(name) then
        table.insert(tests, name)
      end
    end
    table.sort(tests)
    return tests
  end

  local function run_test(test_name)
    print("Running " .. group_name .. "." .. test_name)
    if group.setup then
      group.setup()
    end
    local status, result_or_err = pcall(function()
      return group[test_name]()
    end)
    if group.teardown then
      group.teardown()
    end
    return {
      name = test_name,
      status = status,
      result = result_or_err,
      error = not status and result_or_err or nil,
    }
  end

  local tests = get_tests()
  local results = {}

  for _, test_name in ipairs(tests) do
    table.insert(results, run_test(test_name))
  end

  return results
end

-- Run all modular tests
function M.run_all_tests()
  -- Common setup
  local env = test_utils.setup()

  -- Initialize unified plugin
  require("unified").setup()

  -- Run all test groups
  local groups = {
    { name = "test_basic", module = test_basic },
    { name = "test_rendering", module = test_rendering },
    { name = "test_features", module = test_features },
    { name = "test_multiple_lines", module = test_multiple_lines },
    { name = "test_file_tree", module = test_file_tree },
    { name = "test_hunk_management", module = test_hunk_management },
    { name = "test_hunk_actions", module = test_hunk_actions },
  }

  local all_results = {}

  for _, group in ipairs(groups) do
    local group_results = run_test_group(group.module, group.name)
    for _, result in ipairs(group_results) do
      table.insert(all_results, {
        name = group.name .. "." .. result.name,
        status = result.status,
        error = result.error,
      })
    end
  end

  -- Cleanup
  test_utils.teardown(env)

  -- Print results
  print("\nTest Results:")
  local pass_count, fail_count = 0, 0
  for _, result in ipairs(all_results) do
    local status_str = result.status and "PASS" or "FAIL"
    if result.status then
      pass_count = pass_count + 1
    else
      fail_count = fail_count + 1
    end
    print(string.format("%s: %s", result.name, status_str))
    if result.error then
      print("  Error: " .. tostring(result.error))
    end
  end

  print(string.format("\nSummary: %d passed, %d failed, %d total", pass_count, fail_count, pass_count + fail_count))

  -- Return success if all tests passed
  return fail_count == 0
end

-- Main entry point - run all tests
function M.run()
  print("Running unified.nvim tests")

  -- Run all tests
  local result = M.run_all_tests()

  print(string.format("\nTest result: %s", result and "PASS" or "FAIL"))

  return result
end

-- Expose individual test running for specific tests
function M.run_test(test_name)
  -- Parse test name in format "group.test_function"
  local group_name, func_name = test_name:match("([^%.]+)%.(.+)")

  if not group_name then
    error("Invalid test name format. Use 'module_name.test_name'")
  end

  -- Map group names to modules
  local groups = {
    test_basic = test_basic,
    test_rendering = test_rendering,
    test_features = test_features,
    test_multiple_lines = test_multiple_lines,
    test_file_tree = test_file_tree,
    test_hunk_management = test_hunk_management,
    test_hunk_actions = test_hunk_actions,
  }

  local group = groups[group_name]
  if not group then
    error("Unknown test group: " .. group_name)
  end

  if not group[func_name] then
    error("Unknown test function: " .. func_name .. " in group " .. group_name)
  end

  print("Running test: " .. group_name .. "." .. func_name)
  require("unified").setup()

  local status, result = pcall(function()
    return group[func_name]()
  end)

  if not status then
    print("Test failed: " .. tostring(result))
    error(result)
  end

  print("Test passed!")
  return result
end

return M
