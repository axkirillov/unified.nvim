local M = {}

-- How many recent commits to offer. Keeps the plain vim.ui.select handler
-- usable while still covering the common "diff against something recent" case;
-- fuzzy handlers (telescope, fzf-lua, snacks) cope fine with this many.
local LIMIT = 100

--- Open a picker to choose a base commit, then diff the current buffer against
--- it -- equivalent to running `:Unified <hash>`. Uses vim.ui.select, so it
--- honours whatever picker you have wired up (telescope, fzf-lua, snacks, ...);
--- with the default handler it falls back to a plain numbered list.
function M.pick()
  local git = require("unified.git")
  local cwd = vim.fn.getcwd()

  if not git.is_git_repo(cwd) then
    vim.api.nvim_echo({ { "Not in a git repository.", "WarningMsg" } }, false, {})
    return
  end

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
      require("unified.command").run(choice.hash)
    end)
  end)
end

return M
