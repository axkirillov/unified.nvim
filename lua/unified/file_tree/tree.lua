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

  local function process_status_output(output_lines)
    for line in (output_lines or ""):gmatch("[^\r\n]+") do
      local status = line:sub(1, 2)
      local file = line:sub(4)
      if status:match("^R") then
        local parts = vim.split(file, " -> ")
        if #parts == 2 then
          file = parts[2]
        end
      end
      if status:match("^C") then
        local parts = vim.split(file, " -> ")
        if #parts == 2 then
          file = parts[2]
        end
      end

      if file then
        local path = root_dir .. "/" .. file
        status = (status:gsub("%s", " ") .. " "):sub(1, 2)
        changed_files[path] = status
        has_changes = true
      end
    end
  end

  if commit_ref then
    job.run(
      { "git", "diff", "--name-status", commit_ref },
      { cwd = root_dir },
      function(diff_result, diff_code, diff_err)
        if diff_code == 0 then
          for line in (diff_result or ""):gmatch("[^\r\n]+") do
            local status_char = line:sub(1, 1)
            local file_part = line:match("^[AMDR]%s+(.*)") -- Handle RENAME (R) status from diff too

            if file_part then
              local file = file_part
              if status_char == "R" then
                local parts = vim.split(file_part, "\t")
                if #parts == 2 then
                  file = parts[2] -- Use the new name
                end
              end
              local path = root_dir .. "/" .. file
              changed_files[path] = (status_char .. " "):sub(1, 2)
              has_changes = true
            end
          end
        else
          vim.api.nvim_echo({ { "Error getting git diff: " .. (diff_err or "Unknown error"), "ErrorMsg" } }, false, {})
          vim.schedule(function()
            if callback then
              callback(false)
            end -- Indicate failure
          end)
          return
        end

        local status_result, status_code, status_err = job.await(
          { "git", "status", "--porcelain", "--untracked-files=all" },
          { cwd = root_dir }
        )

        if status_code == 0 then
          process_status_output(status_result)
        else
          vim.api.nvim_echo(
            { { "Warning: Error getting git status: " .. (status_err or "Unknown error"), "WarningMsg" } },
            false,
            {}
          )
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
                callback(true)
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
            callback(true)
          end
        end)
      end
    )
  else
    job.run({ "git", "status", "--porcelain", "--untracked-files=all" }, { cwd = root_dir }, function(result, code, err)
      if code == 0 then
        process_status_output(result)
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
              callback(true)
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
          callback(true)
        end
      end)
    end)
  end
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
