local M = {}

function M.setup(opts)
  local config = require("unified.config")
  local command = require("unified.command")
  local file_tree = require("unified.file_tree")
  config.setup(opts)
  command.setup()
  file_tree.setup()
end

function M.toggle()
  local command = require("unified.command")
  local state = require("unified.state")

  if state.is_active() then
    command.reset()
    return
  end

  -- Reuse the remembered base if there is one; otherwise default to HEAD so the
  -- toggle stays instant. (Bare `:Unified` opens the commit picker instead.)
  local ok, commit_ref = pcall(state.get_commit_base)
  command.run(ok and commit_ref or "HEAD")
end

-- Open a picker to choose the base commit to diff against, then show the diff
-- (the same thing bare `:Unified` does). Exposed so you can map it directly.
function M.pick_commit()
  require("unified.commit_picker").pick()
end

return M
