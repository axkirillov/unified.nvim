-- Module for rendering the FileTree structure into a Neovim buffer

local tree_state = require("unified.file_tree.state").tree_state

local M = {}

-- Render the file tree to a buffer with expanded/collapsed state
function M.render_tree(tree, buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_file_tree")

  -- Clear buffer and previous state
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1) -- Clear old highlights/extmarks
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
  tree_state.line_to_node = {} -- Reset line mapping

  -- Format the directory path more concisely for display
  local header_text = tree.root.path

  -- Replace home directory with ~
  local home = vim.fn.expand("~")
  if header_text:sub(1, #home) == home then
    header_text = "~" .. header_text:sub(#home + 1)
  end

  -- Remove any file:// prefix if present
  header_text = header_text:gsub("^file://", "")

  -- Keep only the last few path components for readability
  if #header_text > 40 then
    local components = {}
    for part in header_text:gmatch("([^/]+)") do
      table.insert(components, part)
    end

    -- If we have many components, keep just the last 3
    if #components > 3 then
      header_text = "~/"
        .. table.concat({ components[#components - 2], components[#components - 1], components[#components] }, "/")
    end
  end

  local lines = {
    "  " .. header_text,
    "  Help: ? ",
    "",
  }

  -- Determine if we're in a git repo by explicitly checking for .git directory
  local has_git_dir = vim.fn.isdirectory(tree.root.path .. "/.git") == 1

  -- Add repository/directory type
  if has_git_dir then
    -- Count files with changes by traversing the tree structure
    local changed_count = 0
    local function count_changes(node)
      if not node.is_dir and node.status and node.status:match("[AMDR?]") then
        changed_count = changed_count + 1
      elseif node.is_dir then
        local children = node:get_children()
        for _, child in ipairs(children) do
          count_changes(child)
        end
      end
    end
    count_changes(tree.root)

    if changed_count > 0 then
      table.insert(lines, "  Git Repository - Changes (" .. changed_count .. ")")
    elseif not tree_state.diff_only then
      -- Only add "No Changes" if not in diff_only mode and count is 0
      table.insert(lines, "  Git Repository - No Changes")
    end
    -- "No changes to display" for diff_only mode will be handled later if no nodes are added
  else
    if #tree.root:get_children() > 0 then
      table.insert(lines, "  Directory View")
    else
      table.insert(lines, "  Empty Directory")
    end
  end

  local highlights = {}
  local extmarks = {}

  -- Keep track of the line number for highlights
  local current_line = #lines - 1

  local function add_node(node, depth)
    -- Skip root node display for cleaner tree
    if node == tree.root then
      -- Add children if directory is expanded (root is always considered expanded conceptually)
      if node.is_dir then
        node:sort() -- Ensure root's children are sorted
        local children = node:get_children()
        for i, child in ipairs(children) do
          add_node(child, 0)
        end
      end
      return
    end

    local is_expanded = tree_state.expanded_dirs[node.path]

    -- Format status indicator
    local status_char = " "
    local status_hl = "Normal"
    if node.status and node.status:match("[AM]") then
      status_char = "M"
      status_hl = "DiffChange"
    elseif node.status and node.status:match("[D]") then
      status_char = "D"
      status_hl = "DiffDelete"
    elseif node.status and node.status:match("[?]") then
      status_char = "?"
      status_hl = "WarningMsg"
    elseif node.status and node.status:match("[R]") then
      status_char = "R"
      status_hl = "DiffChange" -- Or another highlight for renamed
    elseif node.status and node.status:match("[C]") then
      status_char = "C" -- Committed/Cached status from ls-tree
      status_hl = "Comment" -- Use a less prominent highlight
    end

    -- Format directory/file indicators
    local indent = string.rep("  ", depth)
    local icon = node.is_dir and (is_expanded and "" or "") or "" -- Using Nerd Font icons
    local tree_char = icon .. " " -- Icon plus space

    -- Format line with proper spacing
    table.insert(lines, "  " .. indent .. tree_char .. node.name)
    current_line = current_line + 1

    -- Map line to node
    tree_state.line_to_node[current_line] = node

    -- Apply status highlight as virtual text at the beginning
    if status_char ~= " " then
      table.insert(extmarks, {
        line = current_line,
        col = 0, -- Position at the start
        opts = {
          virt_text = { { status_char, status_hl } },
          virt_text_pos = "overlay",
        },
      })
    end

    -- Apply highlight to icon
    local icon_hl = node.is_dir and "Directory" or "Normal"
    table.insert(highlights, {
      line = current_line,
      col = #indent,
      length = #icon,
      hl_group = icon_hl,
    })

    -- Apply highlight to node name
    local name_hl = node.is_dir and "Directory" or "Normal"
    table.insert(highlights, {
      line = current_line,
      col = #indent + #tree_char,
      length = #node.name,
      hl_group = name_hl,
    })

    -- Add children if directory is expanded
    if node.is_dir then
      node:sort() -- Ensure children are sorted before rendering
      local children = node:get_children()
      for _, child in ipairs(children) do
        add_node(child, depth + 1)
      end
    end
  end

  -- Add all nodes starting from root's children
  local initial_line_count = #lines
  add_node(tree.root, 0)
  local final_line_count = #lines

  -- Add "No changes to display" only if in diff_only mode and no file/dir nodes were added
  if tree_state.diff_only and final_line_count == initial_line_count then
    table.insert(lines, "  No changes to display")
  end

  -- Set buffer contents
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  -- Apply text highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buffer, ns_id, hl.hl_group, hl.line, hl.col, hl.col + hl.length)
  end

  -- Apply virtual text extmarks
  for _, em in ipairs(extmarks) do
    vim.api.nvim_buf_set_extmark(buffer, ns_id, em.line, em.col, em.opts)
  end

  -- Add highlighting for the header
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", 1, 0, -1)

  -- Add highlighting for repository status line (adjust index if "No changes" was added)
  local status_line_idx = 3 -- 0-based index for buffer lines
  if #lines > status_line_idx + 1 then -- Check if the line exists (using 1-based #lines)
    local line_content = lines[status_line_idx + 1] -- Get content using 1-based index
    if has_git_dir then
      if line_content:match("Changes") then
        vim.api.nvim_buf_add_highlight(buffer, ns_id, "WarningMsg", status_line_idx, 0, -1)
      elseif line_content:match("No Changes") or line_content:match("No changes to display") then
        vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", status_line_idx, 0, -1)
      end
      -- If neither matches, it might be the first file/dir, no specific highlight needed for the status line itself
    else
      -- Non-git directory view line
      vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", status_line_idx, 0, -1)
    end
  end

  -- Set buffer as non-modifiable
  vim.bo[buffer].modifiable = false

  -- Update tree state references
  tree_state.buffer = buffer
  tree_state.current_tree = tree
end

return M
