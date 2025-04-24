local M = {
  current_tree = nil, -- Instance of the FileTree class
  expanded_dirs = {}, -- Map of expanded directory paths (path -> true)
  line_to_node = {}, -- Map of buffer line number (0-based) to Node object
  buffer = nil, -- Buffer handle for the file tree window
  window = nil, -- Window handle for the file tree window
  root_path = nil, -- The root path used to generate the current tree
  diff_only = false, -- Whether the tree is currently showing only diffs
}

function M.reset_state()
  M.current_tree = nil
  M.expanded_dirs = {}
  M.line_to_node = {}
  M.buffer = nil
  M.window = nil
  M.root_path = nil
  M.diff_only = false
end

return M
