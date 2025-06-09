local hunk_store = require("unified.hunk_store")
local navigation = require("unified.navigation")

local M = {}

function M.setup()
  vim.api.nvim_command("enew!")
  local lines = {}
  for i = 1, 20 do
    table.insert(lines, "line " .. i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

function M.teardown()
  hunk_store.clear(0)
end

local function assert_eq(a, b, msg)
  assert(a == b, msg or string.format("Expected %s, got %s", tostring(a), tostring(b)))
end

function M.test_hunk_store_lifecycle()
  local bufnr = vim.api.nvim_get_current_buf()

  assert_eq(#hunk_store.get(bufnr), 0)

  hunk_store.set(bufnr, { 1, 5, 10 })
  assert_eq(#hunk_store.get(bufnr), 3)
  assert_eq(hunk_store.get(bufnr)[2], 5)

  hunk_store.clear(bufnr)
  assert_eq(#hunk_store.get(bufnr), 0)
end

function M.test_navigation_no_hunks()
  navigation.next_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 1)

  navigation.previous_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 1)
end

function M.test_navigation_jumps()
  local bufnr = vim.api.nvim_get_current_buf()
  hunk_store.set(bufnr, { 5, 10, 15 })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  navigation.next_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 5)

  navigation.next_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 10)

  navigation.previous_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 5)
end

function M.test_navigation_wraps_around()
  local bufnr = vim.api.nvim_get_current_buf()
  hunk_store.set(bufnr, { 5, 10, 15 })

  vim.api.nvim_win_set_cursor(0, { 15, 0 })
  navigation.next_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 5)

  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  navigation.previous_hunk()
  assert_eq(vim.api.nvim_win_get_cursor(0)[1], 15)
end

return M
