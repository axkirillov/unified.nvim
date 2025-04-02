-- This file now acts as a compatibility layer, delegating to the new modular structure.
-- All new development should use require("unified.file_tree.init") or its submodules directly.

local file_tree_init = require("unified.file_tree.init")

-- Expose the public API from the new init module
local M = {
  create_file_tree_buffer = file_tree_init.create_file_tree_buffer,
  show_file_tree = file_tree_init.show_file_tree,
  -- Expose actions if needed for external keymaps, though direct require is better
  actions = file_tree_init.actions,
}

return M
