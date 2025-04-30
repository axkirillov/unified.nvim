-- FileTree implementation
local Node = require("unified.file_tree.node")

local job = require("unified.utils.job")
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
      -- Check if the path corresponds to a directory on the filesystem
      local is_dir = vim.fn.isdirectory(path) == 1
      local new_node = Node.new(filename, is_dir)
      new_node.path = path
      new_node.status = status or " "
      current:add_child(new_node)
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

function FileTree:update_git_status(root_dir, diff_only, commit_ref, callback)
  local changed_files = {}
  local has_changes = false

  local cmd_args
  if commit_ref then
    cmd_args = { "git", "diff", "--name-status", commit_ref }
  else
    cmd_args = { "git", "status", "--porcelain", "--untracked-files=all" }
  end

  job.run(cmd_args, { cwd = root_dir }, function(result, code, err)
    if code == 0 then
      for line in (result or ""):gmatch("[^\r\n]+") do
        local status, file

        if commit_ref and commit_ref ~= "HEAD" then
          status = line:sub(1, 1) .. " "
          file = line:match("^[AMD]%s+(.*)")
        else
          status = line:sub(1, 2)
          file = line:sub(4)
          if status:match("^R") then
            local parts = vim.split(file, " -> ")
            if #parts == 2 then
              file = parts[2]
              status = "R "
            end
          end
        end

        if file then
          local path = root_dir .. "/" .. file
          changed_files[path] = status:gsub("%s", " ")
          has_changes = true
        end
      end
    else
      vim.api.nvim_echo({ { "Error getting git status: " .. (err or "Unknown error"), "ErrorMsg" } }, false, {})
      has_changes = false
      changed_files = {}
    end

    vim.schedule(function()
      if diff_only then
        self.root.children = {}
        self.root.ordered_children = {}

        if has_changes then
          for path, status in pairs(changed_files) do
            self:add_file(path, status)
          end
        else
          if callback then
            callback()
          end
          return
        end
      else
        self:scan_directory(root_dir)
        self:apply_statuses(self.root, changed_files)
      end

      self:update_parent_statuses(self.root)
      self.root:sort()

      if callback then
        callback()
      end
    end)
  end)
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
