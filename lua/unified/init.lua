local M = {}

function M.setup(opts)
  local config = require("unified.config")
  local command = require("unified.command")
  local file_tree = require("unified.file_tree")
  config.setup(opts)
  command.setup()
  file_tree.setup()
end

return M
