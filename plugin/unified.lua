-- unified.nvim plugin loader

if vim.g.loaded_unified_nvim then
  return
end
vim.g.loaded_unified_nvim = true

-- Create a single unified command with optional arguments
vim.api.nvim_create_user_command("Unified", function(opts)
  local args = opts.args

  if args == "" then
    require("unified").toggle_diff()
  elseif args == "toggle" then
    require("unified").toggle_diff()
  elseif args == "refresh" then
    -- Force refresh if diff is displayed
    local unified = require("unified")
    if unified.is_active then
      unified.show_diff()
    else
      vim.api.nvim_echo({ { "No diff currently displayed", "WarningMsg" } }, false, {})
    end
  elseif args == "tree" then
    -- Just show the file tree with diff-only mode (only files with changes)
    require("unified").show_file_tree(nil, false)
  elseif args == "debug" then
    -- Toggle debug mode
    vim.g.unified_debug = not vim.g.unified_debug
    vim.api.nvim_echo({ { "Debug mode " .. (vim.g.unified_debug and "enabled" or "disabled"), "Normal" } }, false, {})
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

      -- Get the unified module
      local unified = require("unified")

      -- If already active, deactivate first to reset state
      if unified.is_active then
        unified.deactivate()
      end

      -- Store current window as main window
      local window = require("unified.window")
      window.main_win = vim.api.nvim_get_current_win()

      -- Show diff for the commit
      local result = unified.show_diff(commit)

      -- Also show the file tree when using commit command
      unified.show_file_tree()

      -- Update global state
      if result then
        unified.is_active = true
      end
    else
      vim.api.nvim_echo({ { "Invalid commit format. Use: Unified commit <hash/ref>", "ErrorMsg" } }, false, {})
    end
  else
    local unified = require("unified")

    -- If already active, deactivate first to reset state
    if unified.is_active then
      unified.deactivate()
    end

    -- Activate the diff display
    unified.activate()
  end
end, {
  nargs = "*",
  complete = function(_, line, _)
    -- Basic command completion
    if line:match("^Unified%s+$") then
      return { "toggle", "refresh", "tree", "commit", "debug" }
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
