-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
  return
end
vim.g.loaded_unified_nvim = true

-- Create a single unified command with optional arguments
vim.api.nvim_create_user_command("Unified", function(opts)
  local args = opts.args

  if args == "toggle" then
    require("unified").toggle_diff()
  elseif args == "refresh" then
    -- Force refresh if diff is displayed
    local unified = require("unified")
    if unified.is_diff_displayed() then
      unified.show_diff()
    else
      vim.api.nvim_echo({ { "No diff currently displayed", "WarningMsg" } }, false, {})
    end
  elseif args:match("^commit%s+") then
    -- Extract commit hash from the command
    local commit = args:match("^commit%s+(.+)$")
    if commit and #commit > 0 then
      -- Validate commit reference
      local buffer = vim.api.nvim_get_current_buf()
      local file_path = vim.api.nvim_buf_get_name(buffer)

      if file_path == "" then
        vim.api.nvim_echo({ { "Buffer has no file name", "ErrorMsg" } }, false, {})
        return
      end

      -- Check if we're in a git repo
      local repo_check = vim.fn.system(
        string.format(
          "cd %s && git rev-parse --is-inside-work-tree 2>/dev/null",
          vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h"))
        )
      )

      if vim.trim(repo_check) ~= "true" then
        vim.api.nvim_echo({ { "File is not in a git repository", "ErrorMsg" } }, false, {})
        return
      end

      -- Try to resolve the commit
      local commit_check = vim.fn.system(
        string.format(
          "cd %s && git rev-parse --verify %s 2>/dev/null",
          vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h")),
          vim.fn.shellescape(commit)
        )
      )

      if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({ { "Invalid git reference: " .. commit, "ErrorMsg" } }, false, {})
        return
      end

      require("unified").show_diff(commit)
    else
      vim.api.nvim_echo({ { "Invalid commit format. Use: Unified commit <hash/ref>", "ErrorMsg" } }, false, {})
    end
  else
    require("unified").show_diff()
  end
end, {
  nargs = "*",
  complete = function(_, line, _)
    -- Basic command completion
    if line:match("^Unified%s+$") then
      return { "toggle", "refresh", "commit" }
    elseif line:match("^Unified%s+commit%s+") then
      -- Try to get recent commits for completion
      local buffer = vim.api.nvim_get_current_buf()
      local file_path = vim.api.nvim_buf_get_name(buffer)

      if file_path == "" then
        return {}
      end

      -- Check if we're in a git repo
      local repo_check = vim.fn.system(
        string.format(
          "cd %s && git rev-parse --is-inside-work-tree 2>/dev/null",
          vim.fn.shellescape(vim.fn.fnamemodify(file_path, ":h"))
        )
      )

      if vim.trim(repo_check) ~= "true" then
        return {}
      end

      -- Provide some common references
      return { "HEAD", "HEAD~1", "HEAD~2", "main", "master" }
    end
    return {}
  end,
})

-- Initialize the plugin with default settings
require("unified").setup()
