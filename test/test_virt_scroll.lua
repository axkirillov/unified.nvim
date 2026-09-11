-- Tests for deleted lines following horizontal scrolling (lua/unified/virt_scroll.lua)
local M = {}

local utils = require("test.test_utils")

-- The text of the first deleted-lines extmark in the buffer, trailing padding stripped.
local function deleted_text(buffer)
  for _, mark in ipairs(utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })) do
    local details = mark[4]
    if details.virt_lines then
      return (details.virt_lines[1][1][1]:gsub("%s+$", ""))
    end
  end
  return nil
end

-- Scroll `win` sideways to `leftcol` and run the sync the WinScrolled autocmd would run.
local function scroll_to(win, leftcol)
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview({ leftcol = leftcol })
  end)
  require("unified.virt_scroll").sync(win)
end

-- Open a repo where a long line has been deleted, show its diff, return buffer + window.
local function open_diff_with_deleted_line(deleted_line)
  local repo = utils.create_git_repo()
  if not repo then
    return nil
  end

  local test_path = utils.create_and_commit_file(repo, "test.txt", { "keep 1", deleted_line, "keep 2" }, "Initial")

  vim.cmd("edit " .. test_path)
  local win = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  vim.wo[win].wrap = false

  vim.api.nvim_buf_set_lines(buffer, 1, 2, false, {}) -- delete the long line
  require("unified.git").show_git_diff_against_commit("HEAD", buffer)

  assert(deleted_text(buffer) == deleted_line, "deleted line should be rendered in full before scrolling")
  return repo, buffer, win
end

function M.test_deleted_lines_follow_horizontal_scroll()
  local long_line = "deleted " .. table.concat(vim.fn.range(1, 40), " ")
  local repo, buffer, win = open_diff_with_deleted_line(long_line)
  if not repo then
    return true
  end

  scroll_to(win, 8)
  assert(
    deleted_text(buffer) == long_line:sub(9),
    "expected deleted line to start at column 9, got: " .. tostring(deleted_text(buffer))
  )

  scroll_to(win, 16)
  assert(deleted_text(buffer) == long_line:sub(17), "deleted line should follow a second scroll")

  scroll_to(win, 0)
  assert(deleted_text(buffer) == long_line, "deleted line should be restored in full when scrolled back")

  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

function M.test_scroll_slices_by_display_columns()
  -- A tab is one character but 'tabstop' display columns wide (8 by default in the
  -- minimal init); slicing by bytes would cut into the following text.
  local line = "\tafter tab"
  local repo, buffer, win = open_diff_with_deleted_line(line)
  if not repo then
    return true
  end

  local tabstop = vim.bo[buffer].tabstop
  scroll_to(win, tabstop)
  assert(
    deleted_text(buffer) == "after tab",
    "expected the tab to be consumed by " .. tabstop .. " columns, got: " .. tostring(deleted_text(buffer))
  )

  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

function M.test_scroll_keeps_padding_to_window_width()
  local repo, buffer, win = open_diff_with_deleted_line("deleted short line")
  if not repo then
    return true
  end

  scroll_to(win, 4)
  local width = vim.api.nvim_win_get_width(win)
  local raw
  for _, mark in ipairs(utils.get_extmarks(buffer, { namespace = "unified_diff", details = true })) do
    if mark[4].virt_lines then
      raw = mark[4].virt_lines[1][1][1]
    end
  end
  assert(raw, "deleted line extmark should still exist")
  assert(
    vim.fn.strdisplaywidth(raw) == width,
    "deleted line should stay padded to the window width (" .. width .. "), got " .. vim.fn.strdisplaywidth(raw)
  )

  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

function M.test_reset_forgets_deleted_lines()
  local repo, buffer, win = open_diff_with_deleted_line("deleted line")
  if not repo then
    return true
  end

  require("unified.command").reset()
  -- Nothing to rewrite any more: syncing after a reset must not recreate extmarks.
  scroll_to(win, 3)
  local marks = vim.api.nvim_buf_get_extmarks(buffer, vim.api.nvim_create_namespace("unified_diff"), 0, -1, {})
  assert(#marks == 0, "syncing after reset should not bring deleted lines back")

  vim.cmd("bdelete!")
  utils.cleanup_git_repo(repo)
  return true
end

return M
