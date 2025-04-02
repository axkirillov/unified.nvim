-- Node implementation for file tree
local Node = {}
Node.__index = Node

function Node.new(name, is_dir)
  local self = setmetatable({}, Node)
  self.name = name
  self.is_dir = is_dir or false
  self.children = {} -- Stores child nodes keyed by name for quick lookup and in order for iteration
  self.status = " " -- Git status of node
  self.path = name
  self.parent = nil
  return self
end

function Node:add_child(node)
  -- Use a temporary table to store ordered children to avoid issues with ipairs on mixed keys
  if not self.children[node.name] then
    self.children[node.name] = node
    -- Ensure we have an ordered list separate from the name map
    if not self.ordered_children then
      self.ordered_children = {}
    end
    table.insert(self.ordered_children, node)
    node.parent = self
  end
  return self.children[node.name]
end

function Node:get_children()
  -- Return the ordered list if it exists, otherwise the potentially sparse table
  return self.ordered_children or self.children
end

function Node:sort()
  -- Sort function: directories first, then alphabetically
  local function compare(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir -- true (directory) comes before false (file)
    end
    return string.lower(a.name) < string.lower(b.name)
  end

  -- Sort the ordered list of children if it exists
  if self.ordered_children then
    table.sort(self.ordered_children, compare)
  end

  -- Recursively sort children's children
  local children_to_sort = self:get_children()
  for _, child in ipairs(children_to_sort) do
    if child.is_dir then
      child:sort()
    end
  end
end

return Node