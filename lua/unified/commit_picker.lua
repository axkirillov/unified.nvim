local M = {}

-- How many recent commits to offer. Keeps the plain vim.ui.select handler
-- usable while still covering the common "diff against something recent" case;
-- fuzzy handlers (telescope, fzf-lua, snacks) cope fine with this many.
local LIMIT = 100

--- Open a picker to choose a base commit, then diff the current buffer against
--- it -- equivalent to running `:Unified <hash>`. Uses vim.ui.select, so it
--- honours whatever picker you have wired up (telescope, fzf-lua, snacks, ...);
--- with the default handler it falls back to a plain numbered list.
---@param opts? { force_tab?: boolean } force_tab opens the chosen diff in a new
---       tab, so `:Unified -t` (no ref) still lands in a tab after picking.
function M.pick(opts)
  opts = opts or {}
  local git = require("unified.git")
  local cwd = vim.fn.getcwd()

  if not git.is_git_repo(cwd) then
    vim.api.nvim_echo({ { "Not in a git repository.", "WarningMsg" } }, false, {})
    return
  end

  -- Capture the window and buffer the picker is invoked from. list_commits and the
  -- vim.ui.select handler both resolve on later ticks, by which point the current
  -- buffer may have changed (focus moved, or a fuzzy picker made its own buffer
  -- current). Without this the diff would bind to whatever is current when the async
  -- chain finishes -- the wrong file, or a nameless picker buffer that diffs nothing.
  -- The picker must behave exactly like `:Unified <hash>` on the originally-focused
  -- buffer.
  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()

  git.list_commits(cwd, LIMIT, function(commits)
    if not commits then
      vim.api.nvim_echo({ { "No commits to pick from.", "WarningMsg" } }, false, {})
      return
    end

    vim.ui.select(commits, {
      prompt = "Diff against commit:",
      format_item = function(c)
        return string.format("%s  %s  (%s, %s)", c.hash, c.subject, c.date, c.author)
      end,
    }, function(choice)
      if not choice then
        return
      end
      -- Re-establish the origin window/buffer before diffing (see above).
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
        if vim.api.nvim_buf_is_valid(origin_buf) and vim.api.nvim_win_get_buf(origin_win) ~= origin_buf then
          vim.api.nvim_win_set_buf(origin_win, origin_buf)
        end
      end
      require("unified.command").run(choice.hash, { force_tab = opts.force_tab })
    end)
  end)
end

return M
