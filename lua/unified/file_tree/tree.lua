-- FileTree implementation
local Node = require("unified.file_tree.node")
local git = require("unified.git")

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
    -- Handle potential missing separator if root_dir is '/'
    if #self.root.path == 1 and self.root.path == "/" then
      rel_path = file_path:sub(#self.root.path + 1)
    elseif #file_path > #self.root.path + 1 then
      rel_path = file_path:sub(#self.root.path + 2)
    else
      -- File is likely the root directory itself, handle appropriately
      -- This case might need refinement depending on usage
      rel_path = "" -- Or handle as an edge case
    end
  end

  -- If rel_path is empty, it might be the root itself or an issue
  if rel_path == "" then
    -- Potentially update root node status if needed
    if status then
      self.root.status = status
    end
    return -- Don't add the root as a child of itself
  end

  -- Split path by directory separator
  local parts = {}
  for part in string.gmatch(rel_path, "[^/\\]+") do
    table.insert(parts, part)
  end

  -- If parts is empty after splitting, something is wrong
  if #parts == 0 then
    return
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
      dir.status = " " -- Intermediate dirs initially have no status
      current:add_child(dir)
    end
    current = dir
  end

  -- Add file node
  local filename = parts[#parts]
  if filename then
    path = path .. "/" .. filename
    -- Check if file node already exists (e.g., added as intermediate dir)
    local existing_node = current.children[filename]
    if existing_node and existing_node.is_dir then
      -- If a directory with the same name exists, update its status
      existing_node.status = status or " "
    elseif not existing_node then
      -- Only add if it doesn't exist
      local file = Node.new(filename, false)
      file.path = path
      file.status = status or " "
      current:add_child(file)
    else
      -- File node exists, update status
      existing_node.status = status or " "
    end
  end
end

-- Scan directory and build tree (basic structure without git status)
function FileTree:scan_directory(dir)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return
  end

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local path = dir .. "/" .. name

    -- Skip hidden files and dirs (starting with .)
    if name:sub(1, 1) ~= "." then
      if type == "directory" then
        self:add_file(path, " ") -- Add directory node
        self:scan_directory(path) -- Recurse
      else
        self:add_file(path, " ") -- Add file node
      end
    end
  end

  -- Sort the tree after scanning
  self.root:sort()
end

-- Update status of files from git
function FileTree:update_git_status(root_dir, diff_only, commit_ref)
  local changed_files = {}
  local has_changes = false

  -- Choose the appropriate command based on the commit_ref
  local cmd
  if commit_ref and commit_ref ~= "HEAD" then
    -- If a specific commit_ref is provided, compare it with the working tree
    cmd =
      string.format("cd %s && git diff --name-status %s", vim.fn.shellescape(root_dir), vim.fn.shellescape(commit_ref))
  else
    -- If no commit_ref or HEAD is provided, use standard git status
    cmd = string.format("cd %s && git status --porcelain", vim.fn.shellescape(root_dir))
  end

  -- Run the chosen command
  local result = vim.fn.system(cmd)
  if vim.v.shell_error == 0 then
    -- Process the command output to get changed files and their statuses
    for line in result:gmatch("[^\r\n]+") do
      local status, file

      if commit_ref and commit_ref ~= "HEAD" then
        -- git diff --name-status output format: A/M/D<TAB>file
        status = line:sub(1, 1) .. " " -- First letter is the status (A/M/D)
        file = line:match("^[AMD]%s+(.*)") -- Get file name after status and whitespace
      else
        -- git status --porcelain output format: XY path
        status = line:sub(1, 2)
        file = line:sub(4)
        -- Handle renamed files (R status)
        if status:match("^R") then
          -- Format is "R  old_path -> new_path"
          local parts = vim.split(file, " -> ")
          if #parts == 2 then
            file = parts[2] -- Use the new path for the tree
            -- We might want to represent the rename differently, but for now, just mark the new path
            status = "R " -- Use 'R' status
          end
        end
      end

      if file then -- Ensure we got a file name
        local path = root_dir .. "/" .. file
        -- Store the status for this file
        changed_files[path] = status:gsub("%s", " ")
        has_changes = true
      end
    end
  end

  -- Handle the case when we're in diff_only mode
  if diff_only then
    local show_all_files_from_commit = false

    -- When no changes are found but we have a commit reference, get all files in that commit
    -- OR always list files if a commit_ref is given (ensures `Unified commit <ref>` works)
    if commit_ref and (not has_changes or true) then -- Simplified logic: always show if commit_ref exists
      show_all_files_from_commit = true
    end

    -- Get all files from commit if needed
    if show_all_files_from_commit then
      local orig_dir = vim.fn.getcwd()
      pcall(vim.cmd, "cd " .. vim.fn.fnameescape(root_dir)) -- Use pcall for safety

      local all_files_cmd = string.format("git ls-tree -r --name-only %s", vim.fn.shellescape(commit_ref))
      local all_files_result = vim.fn.system(all_files_cmd)
      local ls_tree_error = vim.v.shell_error -- Capture error code immediately after system()

      pcall(vim.cmd, "cd " .. vim.fn.fnameescape(orig_dir)) -- Return to original directory

      print(string.format("DEBUG: ls-tree for %s: error=%d, output=[%s]", commit_ref, ls_tree_error, vim.trim(all_files_result)))
      if ls_tree_error == 0 then -- Check the captured error code
        for file in all_files_result:gmatch("[^\r\n]+") do
          local path = root_dir .. "/" .. file
          -- Only add with 'C' status (for commit) if not already present with a real status
          if not changed_files[path] then
            changed_files[path] = "C "
          end
          has_changes = true
        end
      end
    end

    -- Clear existing tree structure before adding changed/commit files
    self.root.children = {}
    self.root.ordered_children = {}

    -- Only add files that have changes or are from the commit
    if has_changes then
      for path, status in pairs(changed_files) do
        self:add_file(path, status)
      end
    else
      -- If still no changes, the tree remains empty (except root)
      return -- Explicitly return if tree should be empty
    end
  else
    -- Not diff_only: Scan the entire directory structure first
    self:scan_directory(root_dir)
    -- Then apply the statuses we found to the existing tree nodes
    self:apply_statuses(self.root, changed_files)
  end

  -- Propagate status up to parent directories
  self:update_parent_statuses(self.root)
  -- Ensure the tree is sorted after updates
  self.root:sort()
end

-- Apply stored statuses to the tree nodes
function FileTree:apply_statuses(node, changed_files)
  if not node.is_dir then
    -- For files, apply status if it exists
    node.status = changed_files[node.path] or " "
  else
    -- For directories, reset status first
    node.status = " "
    -- Process children recursively
    local children = node:get_children()
    for _, child in ipairs(children) do
      self:apply_statuses(child, changed_files)
    end
  end
end

-- Update the status of parent directories based on their children
function FileTree:update_parent_statuses(node)
  if not node.is_dir then
    return " " -- Return file status or space
  end

  local derived_status = " "
  local children = node:get_children()
  for _, child in ipairs(children) do
    local child_status = self:update_parent_statuses(child) -- Recurse first
    -- Propagate 'Modified' status up
    if child_status:match("[AMDR?]") then -- Check for any change status
      derived_status = "M"
      -- No need to check further children if modification found
      -- break -- Optimization: uncomment if only 'M' propagation is needed
    end
  end

  -- Apply derived status only if it's different from space and node isn't root
  if derived_status ~= " " and node ~= self.root then
     node.status = derived_status
  -- If node is root, don't give it a status unless explicitly set elsewhere
  elseif node == self.root then
     node.status = " "
  end

  -- Return the node's own status (could be space, or M if child changed)
  -- Or return derived_status if you want to propagate the highest priority status up
  return node.status or " "
end


return FileTree