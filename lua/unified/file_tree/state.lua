-- Module to manage the state of the file tree UI

local M = {}

-- Store information about the current tree
M.tree_state = {
  current_tree = nil, -- Instance of the FileTree class
  expanded_dirs = {}, -- Map of expanded directory paths (path -> true)
  line_to_node = {}, -- Map of buffer line number (0-based) to Node object
  buffer = nil, -- Buffer handle for the file tree window
  window = nil, -- Window handle for the file tree window
  root_path = nil, -- The root path used to generate the current tree
  diff_only = false, -- Whether the tree is currently showing only diffs
}

-- Function to reset the state, e.g., when closing the tree
function M.reset_state()
  M.tree_state = {
    current_tree = nil,
    expanded_dirs = {},
    line_to_node = {},
    buffer = nil,
    window = nil,
    root_path = nil,
    diff_only = false,
  }
end

return M