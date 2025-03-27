local M = {}

-- Node implementation for file tree
local Node = {}
Node.__index = Node

function Node.new(name, is_dir)
  local self = setmetatable({}, Node)
  self.name = name
  self.is_dir = is_dir or false
  self.children = {}
  self.status = " " -- Git status of node
  self.path = name
  self.parent = nil
  return self
end

function Node:add_child(node)
  if not self.children[node.name] then
    self.children[node.name] = node
    table.insert(self.children, node)
    node.parent = self
  end
  return self.children[node.name]
end

function Node:sort()
  -- Sort function: directories first, then alphabetically
  local function compare(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return string.lower(a.name) < string.lower(b.name)
  end
  
  -- Sort children
  table.sort(self.children, compare)
  
  -- Sort children's children
  for _, child in ipairs(self.children) do
    if child.is_dir then
      child:sort()
    end
  end
end

-- FileTree implementation
local FileTree = {}
FileTree.__index = FileTree

function FileTree.new(root_dir)
  local self = setmetatable({}, FileTree)
  self.root = Node.new(root_dir, true)
  self.root.path = root_dir
  return self
end

-- Add a file path to the tree
function FileTree:add_file(file_path, status)
  -- Remove leading root directory
  local rel_path = file_path
  if file_path:sub(1, #self.root.path) == self.root.path then
    rel_path = file_path:sub(#self.root.path + 2)
  end
  
  -- Split path by directory separator
  local parts = {}
  for part in string.gmatch(rel_path, "[^/\\]+") do
    table.insert(parts, part)
  end
  
  -- Add file to tree
  local current = self.root
  local path = self.root.path
  
  -- Create directories
  for i = 1, #parts - 1 do
    path = path .. "/" .. parts[i]
    local dir = current.children[parts[i]]
    if not dir then
      dir = Node.new(parts[i], true)
      dir.path = path
      dir.status = status or " "
      current:add_child(dir)
    end
    current = dir
  end
  
  -- Add file node
  local filename = parts[#parts]
  if filename then
    path = path .. "/" .. filename
    local file = Node.new(filename, false)
    file.path = path
    file.status = status or " "
    current:add_child(file)
  end
end

-- Scan directory and build tree
function FileTree:scan_directory(dir)
  local handle = vim.loop.fs_scandir(dir)
  if not handle then
    return
  end
  
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    
    local path = dir .. "/" .. name
    
    -- Skip hidden files and dirs (starting with .)
    if name:sub(1, 1) ~= "." then
      if type == "directory" then
        self:add_file(path, " ")
        self:scan_directory(path)
      else
        self:add_file(path, " ")
      end
    end
  end
  
  -- Sort the tree
  self.root:sort()
end

-- Update status of files from git
function FileTree:update_git_status(root_dir)
  -- Get git status for all changes
  local cmd = string.format("cd %s && git status --porcelain", vim.fn.shellescape(root_dir))
  local result = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    return
  end
  
  -- Track changed files for status
  local changed_files = {}
  
  -- Process git status
  for line in result:gmatch("[^\r\n]+") do
    local status = line:sub(1, 2)
    local file = line:sub(4)
    local path = root_dir .. "/" .. file
    
    -- Store the status for this file
    changed_files[path] = status:gsub("%s", " ")
  end
  
  -- Now scan the entire directory structure to create the tree
  self:scan_directory(root_dir)
  
  -- Apply the statuses we found to the tree nodes
  self:apply_statuses(self.root, changed_files)
  
  -- Propagate status up to parent directories
  self:update_parent_statuses(self.root)
end

-- Apply stored statuses to the tree nodes
function FileTree:apply_statuses(node, changed_files)
  if not node.is_dir then
    -- For files, apply status if it exists
    node.status = changed_files[node.path] or " "
  else
    -- For directories, mark status from children later
    node.status = " "
    
    -- Process children
    for _, child in ipairs(node.children) do
      self:apply_statuses(child, changed_files)
    end
  end
end

-- Update the status of parent directories based on their children
function FileTree:update_parent_statuses(node)
  if not node.is_dir then
    return
  end
  
  local status = " "
  for _, child in ipairs(node.children) do
    if child.is_dir then
      self:update_parent_statuses(child)
    end
    
    local child_status = child.status and child.status:gsub("%s", "") or ""
    -- Combine statuses: any modification propagates up
    if child_status ~= "" and child_status ~= " " then
      status = "M"
      break
    end
  end
  
  node.status = status
end

-- Render the file tree to a buffer
function FileTree:render(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_file_tree")
  
  -- Clear buffer
  vim.api.nvim_buf_set_option(buffer, "modifiable", true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
  
  local lines = {}
  local highlights = {}
  
  local function add_node(node, depth)
    local prefix = string.rep("  ", depth)
    local icon = node.is_dir and "▸ " or "  "
    local status_icon = " "
    
    if node.status and node.status:match("[AM]") then
      status_icon = "+"
    elseif node.status and node.status:match("[D]") then
      status_icon = "-"
    end
    
    table.insert(lines, prefix .. icon .. status_icon .. " " .. node.name)
    
    -- Add highlight for node
    local line_idx = #lines - 1
    local hl_group = node.is_dir and "Directory" or "Normal"
    
    -- Add highlight for status
    if status_icon == "+" then
      table.insert(highlights, { line = line_idx, col = #prefix + 2, length = 1, hl_group = "DiffAdd" })
    elseif status_icon == "-" then
      table.insert(highlights, { line = line_idx, col = #prefix + 2, length = 1, hl_group = "DiffDelete" })
    end
    
    -- Add highlight for name
    table.insert(highlights, { 
      line = line_idx, 
      col = #prefix + 4, 
      length = #node.name, 
      hl_group = hl_group 
    })
    
    -- Add children if directory
    if node.is_dir then
      node:sort()
      for _, child in ipairs(node.children) do
        add_node(child, depth + 1)
      end
    end
  end
  
  -- Add root node
  add_node(self.root, 0)
  
  -- Set buffer contents
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  
  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buffer, ns_id, hl.hl_group, hl.line, hl.col, hl.col + hl.length)
  end
  
  -- Set buffer as non-modifiable
  vim.api.nvim_buf_set_option(buffer, "modifiable", false)
end

-- Build and render a file tree for the current buffer's git repository
function M.create_file_tree_buffer(buffer_path)
  -- Get root directory of git repo
  local dir = vim.fn.fnamemodify(buffer_path, ":h")
  local cmd = string.format("cd %s && git rev-parse --show-toplevel", vim.fn.shellescape(dir))
  local root_dir = vim.trim(vim.fn.system(cmd))
  
  if vim.v.shell_error ~= 0 then
    root_dir = dir
  end
  
  -- Create file tree
  local tree = FileTree.new(root_dir)
  tree:scan_directory(root_dir)
  tree:update_git_status(root_dir)
  
  -- Create buffer for file tree
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Unified: File Tree")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "unified_tree")
  
  -- Render file tree to buffer
  tree:render(buf)
  
  return buf
end

-- Store information about the current tree
M.tree_state = {
  current_tree = nil,
  expanded_dirs = {},
  line_to_node = {},
  buffer = nil,
}

-- Toggle node expansion/collapse or open file
function M.toggle_node()
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.tree_state.buffer then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = M.tree_state.line_to_node[line]

  if not node then
    return
  end

  if node.is_dir then
    -- Toggle directory expansion
    if M.tree_state.expanded_dirs[node.path] then
      M.tree_state.expanded_dirs[node.path] = nil
    else
      M.tree_state.expanded_dirs[node.path] = true
    end
    
    -- Re-render the tree
    if M.tree_state.current_tree then
      M.tree_state.current_tree:render(buf)
    end
  else
    -- Open file in the main window
    local win = require("unified").get_main_window()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      vim.cmd("edit " .. vim.fn.fnameescape(node.path))
    end
  end
end

-- Expand node
function M.expand_node()
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.tree_state.buffer then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = M.tree_state.line_to_node[line]

  if node and node.is_dir and not M.tree_state.expanded_dirs[node.path] then
    M.tree_state.expanded_dirs[node.path] = true
    
    -- Re-render the tree
    if M.tree_state.current_tree then
      M.tree_state.current_tree:render(buf)
    end
  end
end

-- Collapse node
function M.collapse_node()
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.tree_state.buffer then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = M.tree_state.line_to_node[line]

  if not node then
    return
  end

  if node.is_dir and M.tree_state.expanded_dirs[node.path] then
    -- Collapse this directory
    M.tree_state.expanded_dirs[node.path] = nil
    
    -- Re-render the tree
    if M.tree_state.current_tree then
      M.tree_state.current_tree:render(buf)
    end
  elseif node.parent then
    -- Go to parent directory
    local parent_line = nil
    for l, n in pairs(M.tree_state.line_to_node) do
      if n.path == node.parent.path then
        parent_line = l
        break
      end
    end
    
    if parent_line then
      vim.api.nvim_win_set_cursor(0, {parent_line + 1, 0})
    end
  end
end

-- Refresh the tree
function M.refresh()
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.tree_state.buffer then
    return
  end
  
  -- Re-create the tree
  local file_path = M.tree_state.root_path
  if file_path then
    local tree = M.create_file_tree_buffer(file_path)
    vim.api.nvim_win_set_buf(0, tree)
  end
end

-- Show help dialog
function M.show_help()
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.tree_state.buffer then
    return
  end
  
  local help_text = {
    "Unified File Explorer Help",
    "------------------------",
    "",
    "Navigation:",
    "  j/k       : Move up/down",
    "  h/l       : Collapse/expand directory",
    "  <CR>/o    : Toggle directory or open file",
    "  -         : Go to parent directory",
    "  <C-j/k>   : Navigate up/down 10 lines",
    "",
    "Actions:",
    "  R         : Refresh the tree",
    "  q         : Close the tree",
    "  ?         : Show this help",
    "",
    "File Status:",
    "  M         : Modified file",
    "  D         : Deleted file",
    "  ?         : Untracked file",
    "",
    "Press any key to close this help"
  }
  
  -- Create a temporary floating window
  local win_width = math.max(40, vim.o.columns / 3)
  local win_height = #help_text
  
  local win_opts = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = math.floor((vim.o.lines - win_height) / 2),
    col = math.floor((vim.o.columns - win_width) / 2),
    style = "minimal",
    border = "rounded"
  }
  
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_text)
  
  local win_id = vim.api.nvim_open_win(help_buf, true, win_opts)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(help_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(help_buf, "bufhidden", "wipe")
  
  -- Add highlighting
  local ns_id = vim.api.nvim_create_namespace("unified_help")
  vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(help_buf, ns_id, "NonText", 1, 0, -1)
  
  -- Highlight section headers
  for i, line in ipairs(help_text) do
    if line:match("^[A-Za-z]") and line:match(":$") then
      vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Statement", i-1, 0, -1)
    end
    -- Highlight keys
    if line:match("^  [^:]+:") then
      local key_end = line:find(":")
      if key_end then
        vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Special", i-1, 2, key_end)
      end
    end
  end
  
  -- Close on any key press
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Space>", "<cmd>close<CR>", {silent = true, noremap = true})
  vim.api.nvim_buf_set_keymap(help_buf, "n", "q", "<cmd>close<CR>", {silent = true, noremap = true})
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<CR>", "<cmd>close<CR>", {silent = true, noremap = true})
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Esc>", "<cmd>close<CR>", {silent = true, noremap = true})
end

-- Go to parent directory node
function M.go_to_parent()
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.tree_state.buffer then
    return
  end
  
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = M.tree_state.line_to_node[line]
  
  if not node or not node.parent then
    return
  end
  
  -- Find the parent node's line
  local parent_line = nil
  for l, n in pairs(M.tree_state.line_to_node) do
    if n == node.parent then
      parent_line = l
      break
    end
  end
  
  if parent_line then
    vim.api.nvim_win_set_cursor(0, {parent_line + 1, 0})
  end
end

-- Render the file tree to a buffer with expanded/collapsed state
function FileTree:render(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("unified_file_tree")
  
  -- Clear buffer
  vim.api.nvim_buf_set_option(buffer, "modifiable", true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
  
  -- Add header with directory name
  local header_text = self.root.path
  
  -- If path is long, truncate it to fit the window width
  if #header_text > 50 then
    -- Get just the last part of the path for display
    local basename = vim.fn.fnamemodify(header_text, ":t")
    local parent = vim.fn.fnamemodify(header_text, ":h:t")
    header_text = "..." .. parent .. "/" .. basename
  end
  
  local lines = {
    "  " .. header_text,
    "  Help: ? ",
    ""
  }
  
  -- Determine if we're in a git repo by checking for .git directory
  local is_git_repo = vim.fn.isdirectory(self.root.path .. "/.git") == 1
  
  -- Add repository/directory type
  if is_git_repo then
    -- Add changed files count if we have any
    local changed_count = 0
    for _, v in pairs(self.root.children) do
      if v.status and v.status:match("[AMD?]") then
        changed_count = changed_count + 1
      end
    end
    
    if changed_count > 0 then
      table.insert(lines, "  Git Repository - Changes (" .. changed_count .. ")")
    else
      table.insert(lines, "  Git Repository - No Changes")
    end
  else
    table.insert(lines, "  Directory View")
  end
  
  local highlights = {}
  local line_to_node = {}
  
  -- Keep track of the line number for highlights
  local current_line = #lines - 1
  
  local function add_node(node, depth)
    -- Skip root node display for cleaner tree
    if node == self.root then
      -- Add children if directory is expanded
      if node.is_dir then
        node:sort()
        for _, child in ipairs(node.children) do
          add_node(child, 0)
        end
      end
      return
    end
    
    local is_expanded = M.tree_state.expanded_dirs[node.path]
    
    -- Format status indicator
    local status_char = " "
    if node.status and node.status:match("[AM]") then
      status_char = "M"
    elseif node.status and node.status:match("[D]") then
      status_char = "D"
    elseif node.status and node.status:match("[?]") then
      status_char = "?"
    end
    
    -- Format directory/file indicators
    local indent = string.rep("  ", depth)
    local tree_char = node.is_dir and (is_expanded and "  " or "  ") or "  "
    
    -- Format line with proper spacing
    table.insert(lines, indent .. tree_char .. node.name)
    current_line = current_line + 1
    
    -- Map line to node
    line_to_node[current_line] = node
    
    -- Apply status highlight at beginning of line
    if status_char ~= " " then
      local hl_group = "Normal"
      if status_char == "M" then
        hl_group = "DiffChange"
      elseif status_char == "D" then
        hl_group = "DiffDelete"
      elseif status_char == "?" then
        hl_group = "WarningMsg"
      end
      
      -- Add status char at the start of the line
      table.insert(highlights, {
        line = current_line,
        col = 0,
        length = 1, 
        hl_group = hl_group,
        text = status_char
      })
    end
    
    -- Apply highlight to node name
    local name_hl = node.is_dir and "Directory" or "Normal"
    table.insert(highlights, {
      line = current_line,
      col = #indent + 2,
      length = #node.name,
      hl_group = name_hl
    })
    
    -- Add children if directory is expanded
    if node.is_dir and is_expanded then
      node:sort()
      for _, child in ipairs(node.children) do
        add_node(child, depth + 1)
      end
    end
  end
  
  -- Add all nodes
  add_node(self.root, 0)
  
  -- Set buffer contents
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  
  -- Apply text highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buffer, ns_id, hl.hl_group, hl.line, hl.col, hl.col + hl.length)
  end
  
  -- Apply virtual text for status indicators
  for _, hl in ipairs(highlights) do
    if hl.text then
      vim.api.nvim_buf_set_extmark(buffer, ns_id, hl.line, 0, {
        virt_text = {{hl.text, hl.hl_group}},
        virt_text_pos = "overlay",
      })
    end
  end
  
  -- Add highlighting for the header
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", 1, 0, -1)
  
  -- Add highlighting for repository status line
  local status_line = 3
  if is_git_repo then
    if lines[4]:match("Changes") then
      vim.api.nvim_buf_add_highlight(buffer, ns_id, "WarningMsg", status_line, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", status_line, 0, -1)
    end
  else
    vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", status_line, 0, -1)
  end
  
  -- Set buffer as non-modifiable
  vim.api.nvim_buf_set_option(buffer, "modifiable", false)
  
  -- Update tree state
  M.tree_state.line_to_node = line_to_node
  M.tree_state.buffer = buffer
  M.tree_state.current_tree = self
end

-- Build and render a file tree for the current buffer's git repository or directory
function M.create_file_tree_buffer(buffer_path)
  -- Store the root path for refresh
  M.tree_state.root_path = buffer_path
  
  -- Check if path exists
  local path_exists = vim.fn.filereadable(buffer_path) == 1 or vim.fn.isdirectory(buffer_path) == 1
  
  -- Get directory from path
  local dir
  if path_exists then
    -- If path exists, use its directory if it's a file, or the path itself if it's a directory
    if vim.fn.isdirectory(buffer_path) == 1 then
      dir = buffer_path
    else
      dir = vim.fn.fnamemodify(buffer_path, ":h")
    end
  else
    -- Path doesn't exist, try using its parent directory
    dir = vim.fn.fnamemodify(buffer_path, ":h")
    
    -- If that doesn't exist either, use the current working directory
    if vim.fn.isdirectory(dir) ~= 1 then
      dir = vim.fn.getcwd()
    end
  end
  
  -- Try to get git root directory
  local cmd = string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(dir))
  local git_root = vim.trim(vim.fn.system(cmd))
  local is_git_repo = vim.v.shell_error == 0 and git_root ~= ""
  
  -- Use git root or fallback to directory
  local root_dir = is_git_repo and git_root or dir
  
  -- Make sure we use the actual git root, not a parent directory
  if is_git_repo then
    -- Verify that git_root is actually a subdirectory of the file system root
    -- This prevents showing too high a directory due to git worktrees or similar
    local fs_root = "/"
    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
      -- On Windows, use drive letter
      fs_root = string.sub(dir, 1, 3) -- e.g., "C:\"
    end
    
    if git_root:sub(1, #fs_root) ~= fs_root then
      -- If somehow git_root doesn't start with fs_root, fall back to dir
      root_dir = dir
    end
    
    -- Double check that the git root really contains a .git directory
    if vim.fn.isdirectory(root_dir .. "/.git") ~= 1 then
      -- If no .git directory, fall back to original directory
      root_dir = dir
    end
  end
  
  -- Log what we're doing in debug mode
  if vim.g.unified_debug then
    print("File Tree - Using root directory: " .. root_dir)
    if is_git_repo then
      print("File Tree - Git repository detected")
    else
      print("File Tree - Not a git repository")
    end
  end
  
  -- Final sanity check - make sure the directory exists
  if vim.fn.isdirectory(root_dir) ~= 1 then
    -- If somehow we got a non-existent directory, fall back to current working directory
    root_dir = vim.fn.getcwd()
    if vim.g.unified_debug then
      print("File Tree - Directory doesn't exist, falling back to: " .. root_dir)
    end
  end
  
  -- Create file tree
  local tree = FileTree.new(root_dir)
  
  -- Always scan the directory first to get the structure
  tree:scan_directory(root_dir)
  
  -- If we're in a git repo, update statuses
  if is_git_repo then
    tree:update_git_status(root_dir)
  end
  
  -- Create buffer for file tree
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Unified: File Tree")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "unified_tree")
  
  -- Render file tree to buffer
  tree:render(buf)
  
  return buf
end

return M