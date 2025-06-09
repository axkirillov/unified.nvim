local H = {}

---@param bufnr integer The buffer number to store hunks for.
---@param lines table A list of line numbers where hunks start.
function H.set(bufnr, lines)
  vim.b[bufnr].unified_hunks = lines
end

---@param bufnr integer The buffer number to retrieve hunks from.
---@return table A list of line numbers where hunks start, or an empty table.
function H.get(bufnr)
  return vim.b[bufnr].unified_hunks or {}
end

---@param bufnr integer The buffer number to clear hunks from.
function H.clear(bufnr)
  vim.b[bufnr].unified_hunks = nil
end

return H
