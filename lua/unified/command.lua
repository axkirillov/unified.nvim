local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Unified", function(opts)
    M.run(opts.args)
  end, {
    nargs = "*",
    complete = function(ArgLead, CmdLine, _)
      if CmdLine:match("^Unified%s+") then
        local suggestions = { "-s", "-t", "HEAD", "HEAD~1", "main", "reset" }
        local filtered_suggestions = {}
        for _, suggestion in ipairs(suggestions) do
          if suggestion:sub(1, #ArgLead) == ArgLead then
            table.insert(filtered_suggestions, suggestion)
          end
        end
        return filtered_suggestions
      end
      return {}
    end,
  })
end

---@param args string Command-line arguments (e.g. "HEAD~1", "-s HEAD", "-t", "reset").
---@param opts? { force_tab?: boolean } Internal: force the new-tab layout regardless
---       of config (used to thread `:Unified -t` through the commit picker).
M.run = function(args, opts)
  opts = opts or {}

  -- Handle reset command
  if args == "reset" then
    M.reset()
    return
  end

  -- Parse flags (order-independent): -s selects the snacks backend, -t opens the
  -- view in a new tab for this invocation. Any remaining token is the commit ref.
  local args_parts = vim.split(args or "", "%s+", { trimempty = true })
  local use_snacks = false
  local flag_tab = false
  local ref_parts = {}
  for _, part in ipairs(args_parts) do
    if part == "-s" then
      use_snacks = true
    elseif part == "-t" then
      flag_tab = true
    else
      table.insert(ref_parts, part)
    end
  end

  local config = require("unified.config")
  -- Open in a new tab when forced (picker thread), requested via -t, or configured.
  local open_in_tab = opts.force_tab or flag_tab or config.values.tab

  -- No ref given: let the user pick a base commit. `:Unified <ref>` still diffs
  -- against an explicit ref; toggle() passes "HEAD" so it stays instant. Thread
  -- the tab preference through so `:Unified -t` opens the chosen diff in a tab.
  -- (`-s` still requires an explicit ref -- its error is reported below.)
  if #ref_parts == 0 and not use_snacks then
    require("unified.commit_picker").pick({ force_tab = open_in_tab })
    return
  end

  local commit_ref
  if use_snacks then
    -- If using snacks, a commit ref is required.
    commit_ref = ref_parts[1]
    if not commit_ref then
      vim.api.nvim_echo(
        { { 'Error: -s requires a git ref argument (e.g., ":Unified -s HEAD")', "ErrorMsg" } },
        false,
        {}
      )
      return
    end
  else
    -- Default backend: the remaining token is the commit ref (or HEAD if omitted).
    commit_ref = ref_parts[1] or "HEAD"
  end

  local git = require("unified.git")
  local state = require("unified.state")
  local cwd = vim.fn.getcwd()

  -- Capture the launch buffer/window now: the async resolve callbacks below run a
  -- tick later, when the current buffer/window may have changed.
  local cur_buf = vim.api.nvim_get_current_buf()
  local cur_win = vim.api.nvim_get_current_win()

  -- Only a real, named file buffer (buftype "" with a name) has a file the inline
  -- diff can follow. Launching from a non-file buffer (a terminal, help,
  -- quickfix, ...) still works -- it shows the repo-wide tree -- but there is
  -- nothing to diff inline.
  local buf_name = vim.api.nvim_buf_get_name(cur_buf)
  local is_file_buf = vim.bo[cur_buf].buftype == "" and buf_name ~= ""

  -- Open the diff view in its own tab, leaving the launch layout untouched. When
  -- launched from a real file, `tab split` branches that same buffer into the new
  -- tab so the inline diff has something to follow; otherwise open an empty tab
  -- and let files open into it from the tree. Returns to cur_win first so a focus
  -- change between command invocation and this async callback can't split the
  -- wrong window.
  local function open_tab()
    if vim.api.nvim_win_is_valid(cur_win) then
      vim.api.nvim_set_current_win(cur_win)
    end
    vim.cmd(is_file_buf and "tab split" or "tabnew")
  end

  if use_snacks then
    -- The snacks picker is repo-wide and rooted at Neovim's cwd (see
    -- file_tree.snacks), so validate the ref against that same repo.
    git.resolve_commit_hash(commit_ref, cwd, function(hash)
      if not hash then
        vim.api.nvim_echo({ { 'Error: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } }, false, {})
        return
      end

      -- Keep the user-provided ref so it can be re-resolved later
      state.set_backend("snacks")
      state.set_active(true)
      if open_in_tab then
        open_tab()
      end
      state.main_win = vim.api.nvim_get_current_win()

      -- This triggers the autocmd which calls snacks_backend.show
      state.set_commit_base(commit_ref)
    end)
  else
    -- Resolve the ref in the buffer's own repo when it is a real file: the inline
    -- diff is computed from *that* repo (see git.show_git_diff_against_commit),
    -- which may differ from nvim's cwd. For a non-file buffer the name is not a
    -- filesystem path, so resolve against nvim's cwd -- the ref is a repo concept,
    -- and the tree is rooted at cwd anyway.
    local resolve_dir = cwd
    if is_file_buf then
      local buf_dir = vim.fn.fnamemodify(buf_name, ":h")
      if vim.fn.isdirectory(buf_dir) == 1 then
        resolve_dir = buf_dir
      end
    end

    git.resolve_commit_hash(commit_ref, resolve_dir, function(hash)
      if not hash then
        vim.api.nvim_echo({ { 'Error: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } }, false, {})
        return
      end

      -- Keep the user-provided ref so it can be re-resolved later
      state.set_backend("default")
      state.set_active(true)

      if is_file_buf then
        -- The inline diff follows the buffer you are in; this is the content
        -- window. The file tree is a side panel for navigation only; it no longer
        -- drives which file is diffed. When opening in a tab, branch this buffer
        -- into the new tab first, then claim that window. Show the diff now, while
        -- the buffer is still focused (set_commit_base below may move focus into
        -- the tree when file_tree.focus is set).
        if open_in_tab then
          open_tab()
          state.main_win = vim.api.nvim_get_current_win()
        else
          state.main_win = cur_win
        end
        require("unified.diff").show(commit_ref, cur_buf)
        require("unified.auto_refresh").setup(cur_buf)

        -- The blocking diff above has populated the hunk store, so land the cursor
        -- on the first hunk now, before set_commit_base may move focus to the tree.
        if config.values.jump_to_first_hunk then
          require("unified.navigation").jump_to_first_hunk(state.main_win, cur_buf)
        end
      else
        -- Launched from a non-file buffer: nothing to diff inline. Open an empty
        -- tab when requested so the tree lands there; either way don't claim the
        -- launch window as the content window -- a terminal is no place to open
        -- files -- so the tree-open path finds/creates a real one in the current
        -- tab (see state.get_main_window). Skip the inline diff, auto-refresh, and
        -- hunk jump, which all need a file.
        if open_in_tab then
          open_tab()
        end
        state.main_win = nil
      end

      -- This triggers the autocmd which calls file_tree.show (repo-wide, cwd-rooted).
      state.set_commit_base(commit_ref)
    end)
  end

  return nil
end

function M.reset()
  local config = require("unified.config")
  local ns_id = config.ns_id
  local hunk_store = require("unified.hunk_store")

  -- Clear highlights, signs and hunk data from ALL buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      vim.fn.sign_unplace("unified_diff", { buffer = buf })
      hunk_store.clear(buf)
    end
  end

  local state = require("unified.state")
  if state.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  -- Close the tree window if one is still open. This window close is
  -- conditional, but the state teardown below is NOT: the tree may already have
  -- been closed (e.g. via `q`) while the inline diff is still active. Previously
  -- the early returns here skipped set_active(false), leaving the plugin stuck
  -- "active" so toggle() could never turn the diff back on.
  local windows = vim.api.nvim_list_wins()
  if state.file_tree_win and vim.api.nvim_win_is_valid(state.file_tree_win) and #windows > 1 then
    vim.api.nvim_win_close(state.file_tree_win, true)
  end
  -- Always drop the tree references, even if the window was already gone (closed
  -- via `q`) or we kept it as the last window. A dangling handle would make the
  -- next :Unified think a tree still exists and try to reuse it.
  state.file_tree_win = nil
  state.file_tree_buf = nil

  state.main_win = nil
  state.set_active(false)
  state.set_backend("default")
end

return M
