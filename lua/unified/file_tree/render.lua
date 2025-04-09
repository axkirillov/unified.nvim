-- Module for rendering the FileTree structure into a Neovim buffer
local tree_state = require("unified.file_tree.state").tree_state

local M = {}

-- Helper: Shorten directory path for display
-- Input: "lua/unified/file_tree/render.lua" -> Output: { "l/u/f/file_tree", "render.lua" }
-- Input: "README.md" -> Output: { "", "README.md" }
local function get_shortened_display_parts(full_path)
  local parts = {}
  for part in string.gmatch(full_path, "[^/]+") do
    table.insert(parts, part)
  end

  if #parts == 0 then
    return { "", "" } -- Should not happen with valid paths
  elseif #parts == 1 then
    return { "", parts[1] } -- File in root
  else
    local shortened_parts = {}
    for i = 1, #parts - 1 do
      table.insert(shortened_parts, string.sub(parts[i], 1, 1))
    end
    -- Shorten all parts except the last directory part
    local display_parts = {}
    for i = 1, #parts - 2 do -- Shorten initial parts
      table.insert(display_parts, string.sub(parts[i], 1, 1))
    end
    -- Add the last directory part fully
    table.insert(display_parts, parts[#parts - 1])

    local shortened_dir_path = table.concat(display_parts, "/")
    local filename = parts[#parts]
    return { shortened_dir_path, filename }
  end
end

-- Helper: Recursively collect file nodes, optionally filtering by status
local function collect_and_filter_files(node, filter_changed_only)
  local files = {}
  local function traverse(current_node)
    if not current_node.is_dir then
      local include_file = true
      if filter_changed_only then
        local status_to_check = current_node.status or " "
        include_file = status_to_check ~= " "
      end
      if include_file then
        table.insert(files, current_node)
      end
    elseif current_node.is_dir then
      local children = current_node:get_children() -- Assuming get_children exists
      for _, child in ipairs(children) do
        traverse(child)
      end
    end
  end
  traverse(node)
  return files
end

-- Render the file tree to a buffer with the new flattened, shortened path structure
function M.render_tree(tree, buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_file_tree")

  -- Clear buffer and previous state
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
  tree_state.line_to_node = {} -- Reset line mapping

  -- === Header Generation (Mostly unchanged) ===
  local header_text = tree.root.path
  local home = vim.fn.expand("~")
  if header_text:sub(1, #home) == home then
    header_text = "~" .. header_text:sub(#home + 1)
  end
  header_text = header_text:gsub("^file://", "")
  if #header_text > 40 then
    local components = {}
    for part in header_text:gmatch("([^/]+)") do
      table.insert(components, part)
    end
    if #components > 3 then
      header_text = "~/"
        .. table.concat({ components[#components - 2], components[#components - 1], components[#components] }, "/")
    end
  end

  local header_lines = {
    "  " .. header_text,
    "  Help: ? ",
    "",
  }

  -- === Collect, Filter, Group, and Sort Files ===
  local all_files = collect_and_filter_files(tree.root, tree_state.diff_only)
  local grouped_files = {}
  local group_keys = {} -- To store unique shortened paths for sorting
  local root_path = tree.root.path
  local root_path_len = #root_path

  for _, file_node in ipairs(all_files) do
    -- Calculate path relative to the root
    local relative_path = file_node.path
    if relative_path:sub(1, root_path_len) == root_path then
      relative_path = relative_path:sub(root_path_len + 1)
      -- Remove leading slash if present after stripping root
      if relative_path:sub(1, 1) == "/" then
        relative_path = relative_path:sub(2)
      end
    end

    local parts = get_shortened_display_parts(relative_path)
    local shortened_path = parts[1]
    local filename = parts[2]
    local filename = parts[2]

    if not grouped_files[shortened_path] then
      grouped_files[shortened_path] = {}
      table.insert(group_keys, shortened_path) -- Add new key for sorting
    end
    table.insert(grouped_files[shortened_path], { name = filename, node = file_node })
  end

  -- Sort group keys (shortened paths) alphabetically, root ("") first
  table.sort(group_keys)

  -- Sort files within each group alphabetically by filename
  for key, files_in_group in pairs(grouped_files) do
    table.sort(files_in_group, function(a, b)
      return a.name < b.name
    end)
  end

  -- === Determine Repository Status Line ===
  local has_git_dir = vim.fn.isdirectory(tree.root.path .. "/.git") == 1
  local status_line = ""
  if has_git_dir then
    local changed_count = 0
    for _, file_node in ipairs(collect_and_filter_files(tree.root, true)) do -- Count all changed files
      changed_count = changed_count + 1
    end

    if changed_count > 0 then
      status_line = "  Git Repository - Changes (" .. changed_count .. ")"
    elseif not tree_state.diff_only then
      status_line = "  Git Repository - No Changes"
    end
    -- "No changes to display" handled later if grouped_files is empty in diff_only mode
  else
    if #all_files > 0 then -- Check if any files exist at all
      status_line = "  Directory View"
    else
      status_line = "  Empty Directory"
    end
  end
  if status_line ~= "" then
    table.insert(header_lines, status_line)
  end

  -- === Render Lines ===
  local lines = vim.list_extend({}, header_lines) -- Start with header
  local highlights = {}
  local extmarks = {}
  local current_line = #lines - 1 -- 0-based index for buffer lines

  for group_idx, shortened_path in ipairs(group_keys) do
    local files_in_group = grouped_files[shortened_path]
    local is_root_group = (shortened_path == "")

    -- Render Path Header (if not root)
    if not is_root_group then
      current_line = current_line + 1
      table.insert(lines, "  " .. shortened_path)
      table.insert(highlights, {
        line = current_line,
        col = 2, -- Start after initial indent
        length = #shortened_path,
        hl_group = "Directory",
      })
      tree_state.line_to_node[current_line] = nil -- Not a selectable node
    end

    -- Render Files in Group
    for file_idx, file_info in ipairs(files_in_group) do
      current_line = current_line + 1
      local node = file_info.node
      local indent = is_root_group and "" or "  " -- Indent files under path headers
      local icon = "" -- File icon
      local tree_char = icon .. " "

      -- Format status indicator
      local status_char = " "
      local status_hl = "Normal"
      if node.status and node.status:match("[AM]") then
        status_char = "M"
        status_hl = "DiffAdd" -- Use DiffAdd for Modified/Added for visibility
      elseif node.status and node.status:match("[D]") then
        status_char = "D"
        status_hl = "DiffDelete"
      elseif node.status and node.status:match("[?]") then
        status_char = "?"
        status_hl = "WarningMsg" -- Untracked
      elseif node.status and node.status:match("[R]") then
        status_char = "R"
        status_hl = "DiffChange" -- Renamed
      elseif node.status and node.status:match("[C]") then
        status_char = "C" -- Committed/Cached status from ls-tree
        status_hl = "Comment" -- Use a less prominent highlight
      end

      -- Format line
      local line_text = "  " .. indent .. tree_char .. file_info.name
      table.insert(lines, line_text)

      -- Map line to node
      tree_state.line_to_node[current_line] = node

      -- Apply status highlight as virtual text
      if status_char ~= " " then
        table.insert(extmarks, {
          line = current_line,
          col = 0, -- Position at the start of the line
          opts = {
            virt_text = { { status_char, status_hl } },
            virt_text_pos = "overlay",
          },
        })
      end

      -- Apply highlight to icon
      local icon_start_col = 2 + #indent -- After initial indent and group indent
      table.insert(highlights, {
        line = current_line,
        col = icon_start_col,
        length = #icon,
        hl_group = "Normal", -- Or specific file icon highlight if desired
      })

      -- Apply highlight to node name
      local name_start_col = icon_start_col + #tree_char
      table.insert(highlights, {
        line = current_line,
        col = name_start_col,
        length = #file_info.name,
        hl_group = "Normal",
      })
    end
  end

  -- Add "No changes to display" only if in diff_only mode and no files were found
  if tree_state.diff_only and #all_files == 0 then
    -- Check if the status line was already added; if so, replace it or add after
    local status_line_idx = #header_lines -- 1-based index where status *might* be
    if #lines >= status_line_idx and lines[status_line_idx]:match("Git Repository") then
      -- If a "No Changes" or similar line exists, we might not need this,
      -- but let's ensure the specific message is there for diff_only.
      -- If we are sure no files were added, this message is appropriate.
      if status_line == "" then -- Only add if no status line was generated
        table.insert(lines, "  No changes to display")
        current_line = current_line + 1
      end
    elseif #all_files == 0 then -- Add if no files and no status line existed
      table.insert(lines, "  No changes to display")
      current_line = current_line + 1
    end
  end

  -- === Final Buffer Operations ===
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  -- Apply text highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buffer, ns_id, hl.hl_group, hl.line, hl.col, hl.col + hl.length)
  end

  -- Apply virtual text extmarks
  for _, em in ipairs(extmarks) do
    vim.api.nvim_buf_set_extmark(buffer, ns_id, em.line, em.col, em.opts)
  end

  -- Add highlighting for the main header
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Title", 0, 0, -1) -- Header path
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", 1, 0, -1) -- Help line

  -- Add highlighting for repository status line (adjust index based on header_lines)
  local status_line_idx_0based = #header_lines - 1 -- 0-based index for buffer lines
  if #lines > status_line_idx_0based + 1 then -- Check if the line exists
    local line_content = lines[status_line_idx_0based + 1] -- Get content using 1-based index
    if line_content then -- Ensure content exists
      if line_content:match("Changes") then
        vim.api.nvim_buf_add_highlight(buffer, ns_id, "WarningMsg", status_line_idx_0based, 0, -1)
      elseif
        line_content:match("No Changes")
        or line_content:match("No changes to display")
        or line_content:match("Directory View")
        or line_content:match("Empty Directory")
      then
        vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", status_line_idx_0based, 0, -1)
      end
    end
  end

  -- Set buffer as non-modifiable
  vim.bo[buffer].modifiable = false

  -- Update tree state references
  tree_state.buffer = buffer
  tree_state.current_tree = tree
end

return M
